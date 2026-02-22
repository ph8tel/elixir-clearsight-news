defmodule ClearsightNews.Repo do
  use Ecto.Repo,
    otp_app: :clearsight_news,
    adapter: Ecto.Adapters.Postgres
end
