defmodule ClearsightNews.Analysis do
  @moduledoc """
  Public API for Groq-backed article analysis.

  `analyse_sentiment/1` makes a direct `Req` call to avoid Instructor's
  tool-calling protocol, which `llama-3.1-8b-instant` handles inconsistently
  on Groq. It parses the JSON content field and casts it into `%SentimentResult{}`
  manually, retrying up to 3 times on parse failure.

  `analyse_rhetoric/1` and `analyse_comparison/2` go through `Instructor` with
  `llama-3.3-70b-versatile`, which handles tool-calling reliably.

  All functions return `{:ok, result_struct}` or `{:error, reason}`.

  Model names are read from env vars **at runtime** on every call so that
  Fly secrets take effect without redeploying:
  - GROQ_SENTIMENT_MODEL  (default: llama-3.1-8b-instant)
  - GROQ_RHETORIC_MODEL   (default: llama-3.3-70b-versatile)
  - GROQ_COMPARISON_MODEL (default: llama-3.3-70b-versatile)
  """

  alias ClearsightNews.Analysis.{SentimentResult, RhetoricResult, ComparisonResult,
                                   Emotions, Rhetoric, Certainty}
  alias Instructor.Adapters.Groq

  # Articles are truncated to 4000 chars before being sent to the model,
  # matching the Python _truncate_text() behaviour.
  @max_chars 4000

  # Classification threshold — matches Python _THRESHOLD = 0.1
  @threshold 0.1

  # System prompt for direct sentiment Req call. Kept as a module attribute so
  # it is easy to find and update without digging into function bodies.
  @sentiment_system_prompt """
  You are a classification engine. Follow these rules exactly.

  RULES:
  - Output MUST be valid JSON.
  - Do NOT include any text outside the JSON.
  - Do NOT include markdown, code fences, or explanations.
  - Do NOT add fields not listed in the schema.
  - Every field MUST be present, even if the value is 0.0.
  - All numeric values must be floats between 0.0 and 1.0.

  SCHEMA (your output MUST match this exactly):
  {
    "tone": "positive" | "neutral" | "negative",
    "emotions": {
      "joy": 0.0, "trust": 0.0, "fear": 0.0, "anger": 0.0,
      "sadness": 0.0, "anticipation": 0.0, "disgust": 0.0, "surprise": 0.0
    },
    "rhetoric": {
      "analytical": 0.0, "supportive": 0.0, "persuasive": 0.0,
      "alarmist": 0.0, "dismissive": 0.0, "sarcastic": 0.0
    },
    "loaded_language": 0.0,
    "certainty": { "certainty": 0.0, "speculation": 0.0 }
  }

  REMEMBER: respond with JSON only.
  """

  # ---------------------------------------------------------------------------
  # Public functions
  # ---------------------------------------------------------------------------

  @doc """
  Run sentiment analysis on `text`.

  Returns `{:ok, %SentimentResult{}}` or `{:error, reason}`.
  Also returns the computed polarity score and sentiment label via
  `classify/1` for convenience.
  """
  def analyse_sentiment(text) when is_binary(text) do
    model = System.get_env("GROQ_SENTIMENT_MODEL", "llama-3.1-8b-instant")

    api_key =
      Application.get_env(:clearsight_news, :groq_api_key) || System.get_env("GROQ_API_KEY")

    body = %{
      model: model,
      messages: [
        %{role: "system", content: @sentiment_system_prompt},
        %{
          role: "user",
          content: "Analyse the sentiment of the following article.\n\nArticle:\n#{truncate(text)}"
        }
      ],
      temperature: 0,
      max_tokens: 512
    }

    # Reuses :instructor_http_options so Req.Test stubs work in tests
    # without any extra config (test.exs already sets this to Req.Test :groq_api).
    req_opts =
      case Application.get_env(:clearsight_news, :instructor_http_options) do
        nil -> [receive_timeout: 60_000]
        http_opts -> [receive_timeout: 60_000] ++ http_opts
      end

    do_sentiment_request(api_key, body, req_opts, 3)
  end

  @doc """
  Run rhetorical analysis on `text`.

  Returns `{:ok, %RhetoricResult{}}` or `{:error, reason}`.
  """
  def analyse_rhetoric(text) when is_binary(text) do
    model = System.get_env("GROQ_RHETORIC_MODEL", "llama-3.3-70b-versatile")

    Instructor.chat_completion(
      [
        model: model,
        response_model: RhetoricResult,
        max_retries: 3,
        messages: [
          %{
            role: "system",
            content: """
            You are a structured news article analyst. You MUST respond ONLY with a JSON object
            that has exactly these top-level keys: overall_tone, sentiment_label, rhetorical_devices, bias_indicators.
            - overall_tone: string (e.g. "neutral", "persuasive", "alarmist", "measured")
            - sentiment_label: one of "positive", "neutral", "negative"
            - rhetorical_devices: array of objects, each with keys "device" (string) and "example" (string)
            - bias_indicators: array of strings
            Do NOT include any other keys. Do NOT include article_body, language, or any other fields.
            """
          },
          %{
            role: "user",
            content: """
            Analyse the rhetorical style of the following article.

            Article:
            #{truncate(text)}
            """
          }
        ]
      ],
      instructor_config()
    )
  end

  @doc """
  Compare two articles for framing, tone, and bias.

  Returns `{:ok, %ComparisonResult{}}` or `{:error, reason}`.
  """
  def analyse_comparison(primary_text, reference_text)
      when is_binary(primary_text) and is_binary(reference_text) do
    model = System.get_env("GROQ_COMPARISON_MODEL", "llama-3.3-70b-versatile")

    Instructor.chat_completion(
      [
        model: model,
        response_model: ComparisonResult,
        max_retries: 3,
        messages: [
          %{
            role: "system",
            content: """
            You are a structured news article analyst. You MUST respond ONLY with a JSON object
            that has exactly these top-level keys: framing_differences, tone_comparison, source_selection, key_differences, bias_assessment.
            - framing_differences: string
            - tone_comparison: string
            - source_selection: string
            - key_differences: string
            - bias_assessment: string
            Do NOT include any other keys.
            """
          },
          %{
            role: "user",
            content: """
            Compare these two articles on the same topic.

            Article 1:
            #{truncate(primary_text)}

            Article 2:
            #{truncate(reference_text)}
            """
          }
        ]
      ],
      instructor_config()
    )
  end

  # ---------------------------------------------------------------------------
  # Score computation  (ported directly from groq_service.py)
  # ---------------------------------------------------------------------------

  @doc """
  Compute a weighted sentiment polarity score in [-1.0, 1.0] from a
  `%SentimentResult{}` struct.

  Formula (weights sum to 1.0):
      score = 0.25 * tone
            + 0.25 * emotion_polarity
            + 0.15 * emotion_intensity
            + 0.15 * rhetoric_polarity
            + 0.10 * loaded_language   (always pushes negative)
            + 0.10 * certainty
  """
  def compute_sentiment_score(%SentimentResult{} = result) do
    tone = tone_polarity(result.tone)

    em = result.emotions || %ClearsightNews.Analysis.Emotions{}

    emotion_polarity =
      (em.joy + em.trust - (em.anger + em.fear + em.sadness + em.disgust)) / 6.0

    emotion_intensity =
      (em.joy + em.trust + em.fear + em.anger + em.sadness + em.disgust +
         em.anticipation + em.surprise) / 8.0

    rh = result.rhetoric || %ClearsightNews.Analysis.Rhetoric{}

    rhetoric_polarity =
      (rh.supportive + rh.analytical - (rh.alarmist + rh.dismissive + rh.sarcastic)) / 5.0

    loaded_language = (result.loaded_language || 0.0) * -1.0

    cert = result.certainty || %ClearsightNews.Analysis.Certainty{}
    certainty = cert.certainty - cert.speculation

    score =
      0.25 * tone +
        0.25 * emotion_polarity +
        0.15 * emotion_intensity +
        0.15 * rhetoric_polarity +
        0.10 * loaded_language +
        0.10 * certainty

    Float.round(max(-1.0, min(1.0, score)), 4)
  end

  @doc """
  Classify a polarity score into a sentiment label atom.

  Returns `:positive`, `:neutral`, or `:negative`.
  The threshold (0.1) matches the Python implementation.
  """
  def classify(score) when score > @threshold, do: :positive
  def classify(score) when score < -@threshold, do: :negative
  def classify(_score), do: :neutral

  @doc "String label for a polarity score — used as a CSS class name in templates."
  def label(score) do
    score |> classify() |> Atom.to_string() |> String.capitalize()
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp tone_polarity("positive"), do: 1.0
  defp tone_polarity("negative"), do: -1.0
  defp tone_polarity(_), do: 0.0

  defp instructor_config do
    api_key =
      Application.get_env(:clearsight_news, :groq_api_key) || System.get_env("GROQ_API_KEY")

    base =
      if is_binary(api_key) and api_key != "" do
        [adapter: Groq, api_key: api_key]
      else
        [adapter: Groq]
      end

    # Allows tests to inject Req.Test plug without touching real HTTP.
    # Set `config :clearsight_news, :instructor_http_options, [plug: {Req.Test, :groq_api}]`
    # in test.exs to enable stubbing.
    case Application.get_env(:clearsight_news, :instructor_http_options) do
      nil -> base
      http_opts -> Keyword.put(base, :http_options, http_opts)
    end
  end

  defp do_sentiment_request(_api_key, _body, _opts, 0) do
    {:error, "sentiment analysis failed after 3 attempts"}
  end

  defp do_sentiment_request(api_key, body, opts, attempts_remaining) do
    case Req.post("https://api.groq.com/openai/v1/chat/completions",
           [auth: {:bearer, api_key}, json: body] ++ opts
         ) do
      {:ok, %{status: 200} = response} ->
        content = get_in(response.body, ["choices", Access.at(0), "message", "content"])

        case cast_sentiment_result(content) do
          {:ok, _} = ok -> ok
          {:error, _} -> do_sentiment_request(api_key, body, opts, attempts_remaining - 1)
        end

      {:ok, %{status: status}} ->
        {:error, "Groq API returned HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cast_sentiment_result(nil), do: {:error, "empty response from model"}

  defp cast_sentiment_result(content) do
    with {:ok, raw} <- Jason.decode(content) do
      em = raw["emotions"] || %{}
      rh = raw["rhetoric"] || %{}
      cert = raw["certainty"] || %{}

      {:ok,
       %SentimentResult{
         tone: raw["tone"],
         loaded_language: raw["loaded_language"] || 0.0,
         emotions: %Emotions{
           joy: em["joy"] || 0.0,
           trust: em["trust"] || 0.0,
           fear: em["fear"] || 0.0,
           anger: em["anger"] || 0.0,
           sadness: em["sadness"] || 0.0,
           anticipation: em["anticipation"] || 0.0,
           disgust: em["disgust"] || 0.0,
           surprise: em["surprise"] || 0.0
         },
         rhetoric: %Rhetoric{
           analytical: rh["analytical"] || 0.0,
           supportive: rh["supportive"] || 0.0,
           persuasive: rh["persuasive"] || 0.0,
           alarmist: rh["alarmist"] || 0.0,
           dismissive: rh["dismissive"] || 0.0,
           sarcastic: rh["sarcastic"] || 0.0
         },
         certainty: %Certainty{
           certainty: cert["certainty"] || 0.0,
           speculation: cert["speculation"] || 0.0
         }
       }}
    end
  end

  defp truncate(text) when byte_size(text) <= @max_chars, do: String.trim(text)

  defp truncate(text) do
    text
    |> String.trim()
    |> binary_part(0, @max_chars)
    |> String.trim_trailing()
    |> Kernel.<>(" ...")
  end
end
