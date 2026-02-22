defmodule ClearsightNews.NewsApi do
  @moduledoc """
  Behaviour for the NewsAPI client. Defining this as a behaviour allows
  `Mox` to generate a mock in tests without hitting the real API.
  """

  @doc """
  Search for news articles matching `query`.
  Returns `{:ok, [article_map]}` or `{:error, reason}`.
  """
  @callback search(query :: String.t(), opts :: keyword()) ::
              {:ok, list(map())} | {:error, String.t()}
end
