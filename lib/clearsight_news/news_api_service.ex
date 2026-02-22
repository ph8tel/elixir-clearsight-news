defmodule ClearsightNews.NewsApiService do
  @moduledoc """
  NewsAPI client backed by `Req`.

  Implements the `ClearsightNews.NewsApi` behaviour. Reads `NEWS_API_KEY`
  from application config (set via the `NEWS_API_KEY` env var).

  Usage:
      {:ok, articles} = ClearsightNews.NewsApiService.search("climate change")
      {:ok, articles} = ClearsightNews.NewsApiService.search("inflation", max: 5)
  """

  @behaviour ClearsightNews.NewsApi

  @base_url "https://newsapi.org/v2/everything"
  @top_headlines_url "https://newsapi.org/v2/top-headlines"
  @default_max 15

  @doc """
  Returns the configured NewsApi implementation module.
  Defaults to `ClearsightNews.NewsApiService`; overridden to
  `ClearsightNews.MockNewsApi` in tests via config.
  """
  def impl, do: Application.get_env(:clearsight_news, :news_api_impl, __MODULE__)

  @impl true
  def search(query, opts \\ []) when is_binary(query) do
    if String.trim(query) == "" do
      {:error, "Query cannot be empty"}
    else
      api_key = Application.get_env(:clearsight_news, :news_api_key)
      max = Keyword.get(opts, :max, @default_max)

      params = [
        q: query,
        pageSize: min(max, 100),
        sortBy: "publishedAt",
        language: "en",
        apiKey: api_key
      ]

      case Req.get(@base_url, params: params) do
        {:ok, %{status: 200, body: %{"status" => "ok", "articles" => raw_articles}}} ->
          articles =
            raw_articles
            |> Enum.map(&process_article/1)
            |> Enum.reject(&is_nil/1)
            |> Enum.take(max)

          {:ok, articles}

        {:ok, %{status: 200, body: %{"status" => status, "message" => message}}} ->
          {:error, "NewsAPI error #{status}: #{message}"}

        {:ok, %{status: status}} ->
          {:error, "NewsAPI returned HTTP #{status}"}

        {:error, exception} ->
          {:error, "Request failed: #{Exception.message(exception)}"}
      end
    end
  end

  @impl true
  def top_headlines(opts \\ []) do
    api_key = Application.get_env(:clearsight_news, :news_api_key)
    max = Keyword.get(opts, :max, 9)

    params = [
      pageSize: min(max, 100),
      language: "en",
      apiKey: api_key
    ]

    case Req.get(@top_headlines_url, params: params) do
      {:ok, %{status: 200, body: %{"status" => "ok", "articles" => raw_articles}}} ->
        articles =
          raw_articles
          |> Enum.map(&process_article/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.take(max)

        {:ok, articles}

      {:ok, %{status: 200, body: %{"status" => status, "message" => message}}} ->
        {:error, "NewsAPI error #{status}: #{message}"}

      {:ok, %{status: status}} ->
        {:error, "NewsAPI returned HTTP #{status}"}

      {:error, exception} ->
        {:error, "Request failed: #{Exception.message(exception)}"}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp process_article(article) do
    title = article["title"] || ""
    url = article["url"] || ""

    # Reject articles with missing required fields or NewsAPI placeholder titles
    if title == "" or url == "" or title == "[Removed]" do
      nil
    else
      %{
        title: title,
        url: url,
        source: get_in(article, ["source", "name"]) || "",
        content: article["content"] || article["description"] || "",
        description: article["description"] || "",
        published_at: parse_datetime(article["publishedAt"])
      }
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end
end
