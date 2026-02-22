defmodule ClearsightNews.Analysis.Emotions do
  @moduledoc "Embedded schema for the eight Plutchik emotion dimensions."
  use Ecto.Schema
  use Instructor

  @primary_key false
  embedded_schema do
    field :joy, :float, default: 0.0
    field :trust, :float, default: 0.0
    field :fear, :float, default: 0.0
    field :anger, :float, default: 0.0
    field :sadness, :float, default: 0.0
    field :anticipation, :float, default: 0.0
    field :disgust, :float, default: 0.0
    field :surprise, :float, default: 0.0
  end
end
