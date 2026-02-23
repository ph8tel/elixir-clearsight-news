defmodule ClearsightNews.Cleaner do
  @moduledoc """
  Periodically prunes articles (and their model_responses via cascade) that
  are older than `@retention_days` days.

  Runs once at startup (after a short delay to let the app fully boot) and
  then every 24 hours. The cascade delete on `model_responses.article_id`
  means only a single DELETE on `articles` is needed.
  """

  use GenServer

  require Logger

  import Ecto.Query

  alias ClearsightNews.{Article, Repo}

  @retention_days 30
  @interval_ms :timer.hours(24)
  # Short delay so the pool is ready before we hit the DB on boot
  @initial_delay_ms :timer.minutes(5)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    Process.send_after(self(), :run, @initial_delay_ms)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:run, state) do
    prune()
    Process.send_after(self(), :run, @interval_ms)
    {:noreply, state}
  end

  @doc """
  Delete articles older than `@retention_days` days. model_responses are
  removed automatically via the `on_delete: :delete_all` FK constraint.
  """
  def prune do
    cutoff = DateTime.utc_now() |> DateTime.add(-@retention_days * 24 * 3600)

    {count, _} = Repo.delete_all(from a in Article, where: a.inserted_at < ^cutoff)

    if count > 0 do
      Logger.info(
        "[Cleaner] pruned #{count} articles older than #{@retention_days} days " <>
          "(model_responses cascade-deleted)"
      )
    end
  end
end
