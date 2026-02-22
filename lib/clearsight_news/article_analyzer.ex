defmodule ClearsightNews.ArticleAnalyzer do
  @moduledoc """
  Shared pipeline for upserting raw NewsAPI articles and running sentiment
  analysis on each one. Used by both `ResultsLive` (search) and
  `SearchLive` (latest headlines).

  The preferred flow for LiveViews is:
    1. `upsert_articles/1`  — fast DB upsert, returns article structs immediately
       with `:analysis_status` set to `"pending"` or `"complete"` (if cached).
    2. Render all cards right away (cached ones show real scores, new ones show
       the "Analyzing…" badge).
    3. For each article whose `:analysis_status` is `"pending"`, fire a
       supervised `Task` that calls `run_sentiment/1` and sends the result back
       to the LiveView via `send(lv_pid, {:analysis_result, article})`.
  """

  alias ClearsightNews.{Article, Analysis, ModelResponse, Repo}
  import Ecto.Query

  @doc """
  Allows a spawned task process to use the Ecto sandbox connection of the
  calling process. No-op in production (Sandbox is not started).
  """
  def allow_sandbox(pid) do
    if sandbox = Process.get({Ecto.Adapters.SQL.Sandbox, Repo}) do
      Ecto.Adapters.SQL.Sandbox.allow(Repo, sandbox, pid)
    end
  end

  @doc """
  Upserts raw NewsAPI article maps into the DB (deduped by URL).

  Returns `{:ok, articles}` where every article struct has:
    - `:analysis_status` — `"complete"` if a cached sentiment result exists,
      `"pending"` otherwise.
    - `:computed_score`, `:computed_result`, `:model_name` — populated from
      cache when available, `nil` otherwise.
  """
  def upsert_articles([]), do: {:ok, []}

  def upsert_articles(raw_articles) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(raw_articles, fn a ->
        Map.merge(a, %{inserted_at: now, updated_at: now})
      end)

    {_count, articles} =
      Repo.insert_all(Article, rows,
        on_conflict: {:replace, [:title, :content, :description, :updated_at]},
        conflict_target: :url,
        returning: true
      )

    article_ids = Enum.map(articles, & &1.id)

    cached_by_id =
      Repo.all(
        from mr in ModelResponse,
          where:
            mr.article_id in ^article_ids and
              mr.response_type == "sentiment" and
              mr.status == "complete",
          order_by: [desc: mr.inserted_at]
      )
      |> Enum.uniq_by(& &1.article_id)
      |> Map.new(&{&1.article_id, &1})

    articles =
      Enum.map(articles, fn article ->
        case Map.get(cached_by_id, article.id) do
          %ModelResponse{} = mr ->
            article
            |> Map.put(:computed_score, mr.computed_score)
            |> Map.put(:computed_result, mr.computed_result)
            |> Map.put(:analysis_status, "complete")
            |> Map.put(:model_name, mr.model_name)

          nil ->
            article
            |> Map.put(:computed_score, nil)
            |> Map.put(:computed_result, nil)
            |> Map.put(:analysis_status, "pending")
            |> Map.put(:model_name, nil)
        end
      end)

    {:ok, articles}
  end

  @doc "Run sentiment analysis for a single article and persist the ModelResponse row."
  def run_sentiment(article) do
    model_name = System.get_env("GROQ_SENTIMENT_MODEL", "llama-3.3-70b-versatile")
    text = article.content || article.description || ""

    {:ok, response} =
      %ModelResponse{}
      |> ModelResponse.changeset(%{
        article_id: article.id,
        response_type: "sentiment",
        model_name: model_name,
        status: "pending"
      })
      |> Repo.insert()

    start = System.monotonic_time(:millisecond)

    {status, computed_score, computed_result, error_message} =
      case Analysis.analyse_sentiment(text) do
        {:ok, result} ->
          score = Analysis.compute_sentiment_score(result)
          result_map = deep_struct_to_map(result)
          {"complete", score, result_map, nil}

        {:error, reason} ->
          {"error", nil, nil, inspect(reason)}
      end

    latency_ms = System.monotonic_time(:millisecond) - start

    response
    |> ModelResponse.complete_changeset(%{
      status: status,
      latency_ms: latency_ms,
      computed_score: computed_score,
      computed_result: computed_result,
      error_message: error_message
    })
    |> Repo.update!()

    article
    |> Map.put(:computed_score, computed_score)
    |> Map.put(:computed_result, computed_result)
    |> Map.put(:analysis_status, status)
    |> Map.put(:model_name, model_name)
  end

  def deep_struct_to_map(%_struct{} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.map(fn {k, v} -> {k, deep_struct_to_map(v)} end)
    |> Enum.into(%{})
  end

  def deep_struct_to_map([head | tail]), do: [deep_struct_to_map(head) | deep_struct_to_map(tail)]
  def deep_struct_to_map(nil), do: nil
  def deep_struct_to_map(value), do: value
end
