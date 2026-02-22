defmodule ClearsightNews.Article do
  use Ecto.Schema
  import Ecto.Changeset

  alias ClearsightNews.ModelResponse

  schema "articles" do
    field :url, :string
    field :title, :string
    field :source, :string
    field :content, :string
    field :description, :string
    field :published_at, :utc_datetime

    has_many :model_responses, ModelResponse
    has_many :reference_responses, ModelResponse, foreign_key: :reference_article_id

    timestamps(type: :utc_datetime)
  end

  @required [:url, :title]
  @optional [:source, :content, :description, :published_at]

  def changeset(article, attrs) do
    article
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint(:url)
  end
end
