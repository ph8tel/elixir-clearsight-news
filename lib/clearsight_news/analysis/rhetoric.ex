defmodule ClearsightNews.Analysis.Rhetoric do
  @moduledoc "Embedded schema for the six rhetorical style dimensions."
  use Ecto.Schema
  use Instructor

  @primary_key false
  embedded_schema do
    field :analytical, :float, default: 0.0
    field :supportive, :float, default: 0.0
    field :persuasive, :float, default: 0.0
    field :alarmist, :float, default: 0.0
    field :dismissive, :float, default: 0.0
    field :sarcastic, :float, default: 0.0
  end
end
