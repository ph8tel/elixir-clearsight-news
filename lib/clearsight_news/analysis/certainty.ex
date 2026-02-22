defmodule ClearsightNews.Analysis.Certainty do
  @moduledoc "Embedded schema for certainty vs speculation scores."
  use Ecto.Schema
  use Instructor

  @primary_key false
  embedded_schema do
    field :certainty, :float, default: 0.0
    field :speculation, :float, default: 0.0
  end
end
