defmodule ClearsightNews.Repo.Migrations.CreateArticles do
  use Ecto.Migration

  def change do
    create table(:articles) do
      add :url, :string, null: false
      add :title, :string, null: false
      add :source, :string
      add :content, :text
      add :description, :text
      add :published_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:articles, [:url])
  end
end
