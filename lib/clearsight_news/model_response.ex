defmodule ClearsightNews.ModelResponse do
  use Ecto.Schema
  import Ecto.Changeset

  alias ClearsightNews.Article

  @response_types ~w(sentiment rhetoric comparison)
  @statuses ~w(pending complete error)

  schema "model_responses" do
    belongs_to :article, Article
    belongs_to :reference_article, Article

    field :response_type, :string
    field :model_name, :string
    field :status, :string, default: "pending"
    field :prompt_tokens, :integer
    field :completion_tokens, :integer
    field :latency_ms, :integer
    field :raw_response, :map
    field :computed_score, :float
    field :computed_result, :map
    field :error_message, :string

    timestamps(type: :utc_datetime)
  end

  @required [:article_id, :response_type, :model_name, :status]
  @optional [
    :reference_article_id,
    :prompt_tokens,
    :completion_tokens,
    :latency_ms,
    :raw_response,
    :computed_score,
    :computed_result,
    :error_message
  ]

  def changeset(response, attrs) do
    response
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:response_type, @response_types)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:article_id)
    |> foreign_key_constraint(:reference_article_id)
  end

  @doc "Changeset for patching a pending response with completed results."
  def complete_changeset(response, attrs) do
    response
    |> cast(attrs, [
      :status,
      :prompt_tokens,
      :completion_tokens,
      :latency_ms,
      :raw_response,
      :computed_score,
      :computed_result,
      :error_message
    ])
    |> validate_inclusion(:status, @statuses)
  end
end
