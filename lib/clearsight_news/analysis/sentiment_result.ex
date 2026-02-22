defmodule ClearsightNews.Analysis.SentimentResult do
  @moduledoc """
  Instructor-backed schema for sentiment analysis of a news article.

  The model is asked to return a structured JSON object with tone,
  emotion dimensions, rhetorical style scores, loaded language density,
  and certainty vs speculation. `compute_sentiment_score/1` in
  `ClearsightNews.Analysis` derives the final [-1, 1] polarity from
  these fields.
  """
  use Ecto.Schema
  use Instructor
  import Ecto.Changeset

  alias ClearsightNews.Analysis.{Emotions, Rhetoric, Certainty}

  @llm_doc """
  Analyse the sentiment and tone of a news article.

  Return a JSON object with these fields:
  - tone: "positive", "neutral", or "negative" — the overall tone of the article
  - emotions: object with keys joy, trust, fear, anger, sadness, anticipation,
    disgust, surprise — each a float between 0.0 and 1.0 indicating intensity
  - rhetoric: object with keys analytical, supportive, persuasive, alarmist,
    dismissive, sarcastic — each a float between 0.0 and 1.0
  - loaded_language: float 0.0–1.0, how much charged/emotional language is used
  - certainty: object with keys certainty and speculation — each 0.0–1.0,
    representing how assertively vs speculatively the article is written

  All numeric values must be between 0.0 and 1.0.
  """

  @primary_key false
  embedded_schema do
    field :tone, :string
    embeds_one :emotions, Emotions
    embeds_one :rhetoric, Rhetoric
    field :loaded_language, :float, default: 0.0
    embeds_one :certainty, Certainty
  end

  @impl true
  def validate_changeset(changeset) do
    changeset
    |> validate_required([:tone])
    |> validate_inclusion(:tone, ["positive", "neutral", "negative"])
    |> validate_float_range(:loaded_language)
  end

  defp validate_float_range(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if value >= 0.0 and value <= 1.0, do: [], else: [{field, "must be between 0.0 and 1.0"}]
    end)
  end
end
