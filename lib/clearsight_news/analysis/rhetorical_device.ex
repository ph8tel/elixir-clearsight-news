defmodule ClearsightNews.Analysis.RhetoricalDevice do
  @moduledoc "Embedded schema for a single rhetorical device with a quoted example."
  use Ecto.Schema
  use Instructor

  @primary_key false
  embedded_schema do
    field :device, :string
    field :example, :string
  end
end
