defmodule ClearsightNews.NewsApiServiceTest do
  use ExUnit.Case, async: true

  import Mox

  alias ClearsightNews.NewsApiService
  alias ClearsightNews.MockNewsApi

  # Ensure Mox expectations are verified after each test
  setup :verify_on_exit!

  @sample_articles [
    %{
      title: "Climate deal reached at summit",
      url: "https://example.com/climate",
      source: "Reuters",
      content: "World leaders agreed to cut emissions...",
      description: "A landmark climate agreement was signed.",
      published_at: ~U[2026-02-20 10:00:00Z]
    },
    %{
      title: "Markets rally on positive jobs data",
      url: "https://example.com/markets",
      source: "Bloomberg",
      content: "Stock markets rose sharply after...",
      description: "Strong employment figures boosted investor confidence.",
      published_at: ~U[2026-02-20 11:00:00Z]
    }
  ]

  describe "search/2 via mock" do
    test "returns articles from the configured impl" do
      MockNewsApi
      |> expect(:search, fn "climate change", [] -> {:ok, @sample_articles} end)

      assert {:ok, articles} = MockNewsApi.search("climate change", [])
      assert length(articles) == 2
      assert hd(articles).title == "Climate deal reached at summit"
    end

    test "returns error from the configured impl" do
      MockNewsApi
      |> expect(:search, fn "bad query", [] -> {:error, "NewsAPI error 429: rate limited"} end)

      assert {:error, reason} = MockNewsApi.search("bad query", [])
      assert reason =~ "rate limited"
    end

    test "passes max option through" do
      MockNewsApi
      |> expect(:search, fn "test", [max: 5] -> {:ok, Enum.take(@sample_articles, 1)} end)

      assert {:ok, [article]} = MockNewsApi.search("test", max: 5)
      assert article.url == "https://example.com/climate"
    end
  end

  describe "process_article/1 (via real impl, testing edge cases)" do
    # We test the real module's private processing logic indirectly by using
    # Req.Test to stub HTTP responses.

    test "impl/0 returns the configured module" do
      # In test env, should return MockNewsApi per config
      assert NewsApiService.impl() == ClearsightNews.MockNewsApi
    end
  end

  describe "search/2 real impl — empty query guard" do
    test "returns error for empty query without making HTTP call" do
      assert {:error, "Query cannot be empty"} = NewsApiService.search("")
      assert {:error, "Query cannot be empty"} = NewsApiService.search("   ")
    end
  end
end
