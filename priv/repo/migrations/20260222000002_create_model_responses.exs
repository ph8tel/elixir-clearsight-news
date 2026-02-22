defmodule ClearsightNews.Repo.Migrations.CreateModelResponses do
  use Ecto.Migration

  def change do
    create table(:model_responses) do
      add :article_id, references(:articles, on_delete: :delete_all), null: false
      add :reference_article_id, references(:articles, on_delete: :nilify_all)
      add :response_type, :string, null: false
      add :model_name, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :prompt_tokens, :integer
      add :completion_tokens, :integer
      add :latency_ms, :integer
      add :raw_response, :map
      add :computed_score, :float
      add :computed_result, :map
      add :error_message, :text

      timestamps(type: :utc_datetime)
    end

    create index(:model_responses, [:article_id])
    create index(:model_responses, [:reference_article_id])
    create index(:model_responses, [:status])
    create index(:model_responses, [:article_id, :response_type])
  end
end
