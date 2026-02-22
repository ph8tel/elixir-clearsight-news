defmodule ClearsightNews.Analysis do
  @moduledoc """
  Public API for Groq-backed article analysis.

  All three analysis types go through `instructor`, which handles JSON
  parsing, validation, and retries automatically. Each function returns
  `{:ok, result_struct}` or `{:error, reason}`.

  Model names are read from env vars **at runtime** on every call so that
  Fly secrets take effect without redeploying:
  - GROQ_SENTIMENT_MODEL  (default: llama-3.3-70b-versatile)
  - GROQ_RHETORIC_MODEL   (default: llama-3.3-70b-versatile)
  - GROQ_COMPARISON_MODEL (default: llama-3.3-70b-versatile)
  """

  alias ClearsightNews.Analysis.{SentimentResult, RhetoricResult, ComparisonResult}
  alias Instructor.Adapters.Groq

  # Articles are truncated to 4000 chars before being sent to the model,
  # matching the Python _truncate_text() behaviour.
  @max_chars 4000

  # Classification threshold — matches Python _THRESHOLD = 0.1
  @threshold 0.1

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
    model = System.get_env("GROQ_SENTIMENT_MODEL", "llama-3.3-70b-versatile")

    Instructor.chat_completion(
      [
        model: model,
        response_model: SentimentResult,
        max_retries: 3,
        messages: [
          %{
            role: "system",
            content: """
            You are a structured news article analyst. You MUST respond ONLY with a JSON object
            that has exactly these top-level keys: tone, emotions, rhetoric, loaded_language, certainty.
            - tone: one of "positive", "neutral", "negative"
            - emotions: object with keys joy, trust, fear, anger, sadness, anticipation, disgust, surprise (each 0.0–1.0)
            - rhetoric: object with keys analytical, supportive, persuasive, alarmist, dismissive, sarcastic (each 0.0–1.0)
            - loaded_language: float 0.0–1.0
            - certainty: object with keys certainty and speculation (each 0.0–1.0)
            Do NOT include any other keys. Do NOT include article_body, language, or any other fields.
            """
          },
          %{
            role: "user",
            content: """
            Analyse the sentiment of the following article.

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

  defp truncate(text) when byte_size(text) <= @max_chars, do: String.trim(text)

  defp truncate(text) do
    text
    |> String.trim()
    |> binary_part(0, @max_chars)
    |> String.trim_trailing()
    |> Kernel.<>(" ...")
  end
end
