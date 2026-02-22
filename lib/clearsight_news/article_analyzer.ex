defmodule ClearsightNews.ArticleAnalyzer do
  @moduledoc """
  Shared pipeline for upserting raw NewsAPI articles and running sentiment
  analysis on each one. Used by both `ResultsLive` (search) and
  `SearchLive` (latest headlines).
  """

  alias ClearsightNews.{Article, Analysis, ModelResponse, Repo}
  import Ecto.Query

  @doc """
  Upserts a list of raw article maps into the DB (deduped by URL) and runs
  sentiment analysis concurrently on each one.

  Returns `{:ok, articles_with_scores}` where each article struct has a
  `:computed_score` float (or `nil` on error/timeout).
  """
  def upsert_and_analyse(raw_articles) do
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

    # Reuse any existing complete sentiment results so we don't hammer
    # the Groq API on every page load for already-analysed articles.
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

    analysed =
      articles
      |> Task.async_stream(
        fn article ->
          case Map.get(cached_by_id, article.id) do
            %ModelResponse{} = mr ->
              article
              |> Map.put(:computed_score, mr.computed_score)
              |> Map.put(:computed_result, mr.computed_result)
              |> Map.put(:analysis_status, "complete")
              |> Map.put(:model_name, mr.model_name)

            nil ->
              run_sentiment(article)
          end
        end,
        max_concurrency: 5,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.zip(articles)
      |> Enum.map(fn
        {{:ok, article_with_score}, _} -> article_with_score

        {{:exit, _}, article} ->
          article
          |> Map.put(:computed_score, nil)
          |> Map.put(:computed_result, nil)
          |> Map.put(:analysis_status, "error")
          |> Map.put(:model_name, nil)
      end)

    {:ok, analysed}
  end

  @doc "Run sentiment analysis for a single article and persist the ModelResponse row."
  def run_sentiment(article) do
    model_name = System.get_env("GROQ_SENTIMENT_MODEL", "llama-3.1-8b-instant")
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

  defp deep_struct_to_map(%_struct{} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.map(fn {k, v} -> {k, deep_struct_to_map(v)} end)
    |> Enum.into(%{})
  end

  defp deep_struct_to_map([head | tail]), do: [deep_struct_to_map(head) | deep_struct_to_map(tail)]
  defp deep_struct_to_map(nil), do: nil
  defp deep_struct_to_map(value), do: value
end
