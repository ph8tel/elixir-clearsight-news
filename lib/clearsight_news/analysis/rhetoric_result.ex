defmodule ClearsightNews.Analysis.RhetoricResult do
  @moduledoc """
  Instructor-backed schema for rhetorical analysis of a news article.

  Returns a structured breakdown of tone, rhetorical devices used,
  quoted examples, and bias indicators.
  """
  use Ecto.Schema
  use Instructor
  import Ecto.Changeset

  alias ClearsightNews.Analysis.RhetoricalDevice

  @llm_doc """
  Analyse the rhetorical style of a news article.

  Return a JSON object with these fields:
  - overall_tone: string describing the dominant tone (e.g. "neutral",
    "persuasive", "alarmist", "celebratory", "measured")
  - sentiment_label: "positive", "neutral", or "negative"
  - rhetorical_devices: array of objects, each with:
    - device: name of the rhetorical device (e.g. "appeal to emotion",
      "loaded language", "repetition", "metaphor")
    - example: a direct quote from the article illustrating the device
  - bias_indicators: array of strings describing any framing choices,
    selective emphasis, or language that suggests a particular viewpoint
  """

  @primary_key false
  embedded_schema do
    field :overall_tone, :string
    field :sentiment_label, :string
    embeds_many :rhetorical_devices, RhetoricalDevice
    field :bias_indicators, {:array, :string}, default: []
  end

  @impl true
  def validate_changeset(changeset) do
    changeset
    |> validate_required([:overall_tone, :sentiment_label])
    |> validate_inclusion(:sentiment_label, ["positive", "neutral", "negative"])
  end
end
