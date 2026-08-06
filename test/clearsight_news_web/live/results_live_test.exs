defmodule ClearsightNewsWeb.ResultsLiveTest do
  use ClearsightNewsWeb.ConnCase

  alias ClearsightNews.{Article, ModelResponse, Repo}

  import Phoenix.LiveViewTest
  import Mox

  setup :verify_on_exit!

  test "GET /results without query redirects home", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/results")
  end

  test "GET /results renders columns with loading state", %{conn: conn} do
    ClearsightNews.MockNewsApi
    |> stub(:search, fn _query, _opts -> {:ok, []} end)

    {:ok, _view, html} = live(conn, ~p"/results?q=test")
    # Page title and query present
    assert html =~ "test"
    # Three column headings rendered
    assert html =~ "Positive"
    assert html =~ "Neutral"
    assert html =~ "Negative"
  end

  test "mobile sentiment tabs render and switch active panel", %{conn: conn} do
    ClearsightNews.MockNewsApi
    |> stub(:search, fn _query, _opts -> {:ok, []} end)

    {:ok, view, _html} = live(conn, ~p"/results?q=test")

    assert has_element?(view, "#results-mobile-tabs")
    assert has_element?(view, "#tab-positive.tab-active")

    view
    |> element("#tab-negative")
    |> render_click()

    assert has_element?(view, "#tab-negative.tab-active")
    refute has_element?(view, "#tab-positive.tab-active")
  end

  test "mobile active panel shows selected sentiment column content", %{conn: conn} do
    positive = insert_article_with_score("Positive Title", 0.7)
    neutral = insert_article_with_score("Neutral Title", 0.0)
    negative = insert_article_with_score("Negative Title", -0.6)

    ClearsightNews.MockNewsApi
    |> stub(:search, fn _query, _opts ->
      {:ok, [raw_article(positive), raw_article(neutral), raw_article(negative)]}
    end)

    {:ok, view, _html} = live(conn, ~p"/results?q=test")

    assert_eventually(fn ->
      has_element?(view, "#mobile-active-column .card-title a", "Positive Title")
    end)

    mobile_panel_html = view |> element("#mobile-active-column") |> render()
    assert mobile_panel_html =~ "Positive Title"
    refute mobile_panel_html =~ "Neutral Title"
    refute mobile_panel_html =~ "Negative Title"

    view
    |> element("#tab-neutral")
    |> render_click()

    assert_eventually(fn ->
      has_element?(view, "#mobile-active-column .card-title a", "Neutral Title")
    end)

    mobile_panel_html = view |> element("#mobile-active-column") |> render()
    assert mobile_panel_html =~ "Neutral Title"
    refute mobile_panel_html =~ "Positive Title"
    refute mobile_panel_html =~ "Negative Title"

    view
    |> element("#tab-negative")
    |> render_click()

    assert_eventually(fn ->
      has_element?(view, "#mobile-active-column .card-title a", "Negative Title")
    end)

    mobile_panel_html = view |> element("#mobile-active-column") |> render()
    assert mobile_panel_html =~ "Negative Title"
    refute mobile_panel_html =~ "Positive Title"
    refute mobile_panel_html =~ "Neutral Title"
  end

  test "selecting primary and reference enables compare navigation", %{conn: conn} do
    primary = insert_article_with_score("Primary Candidate", 0.5)
    reference = insert_article_with_score("Reference Candidate", 0.4)

    ClearsightNews.MockNewsApi
    |> stub(:search, fn _query, _opts -> {:ok, [raw_article(primary), raw_article(reference)]} end)

    {:ok, view, _html} = live(conn, ~p"/results?q=test")

    assert_eventually(fn ->
      has_element?(
        view,
        "#mobile-active-column button[phx-click='select_primary'][phx-value-id='#{primary.id}']"
      )
    end)

    refute has_element?(view, "#results-header-actions button[phx-click='compare']")

    view
    |> element(
      "#mobile-active-column button[phx-click='select_primary'][phx-value-id='#{primary.id}']"
    )
    |> render_click()

    refute has_element?(view, "#results-header-actions button[phx-click='compare']")

    view
    |> element(
      "#mobile-active-column button[phx-click='select_reference'][phx-value-id='#{reference.id}']"
    )
    |> render_click()

    assert has_element?(view, "#results-header-actions button[phx-click='compare']")

    view
    |> element("#results-header-actions button[phx-click='compare']")
    |> render_click()

    assert_redirect(view, ~p"/compare?primary=#{primary.id}&reference=#{reference.id}")
  end

  defp insert_article_with_score(title, score) do
    article =
      %Article{}
      |> Article.changeset(%{
        title: title,
        url: "https://example.com/#{slug(title)}",
        source: "Spec Source",
        description: "Description for #{title}",
        content: "Content for #{title}",
        published_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert!()

    %ModelResponse{}
    |> ModelResponse.changeset(%{
      article_id: article.id,
      response_type: "sentiment",
      model_name: "test-model",
      status: "complete",
      computed_score: score,
      computed_result: %{}
    })
    |> Repo.insert!()

    article
  end

  defp raw_article(article) do
    %{
      title: article.title,
      url: article.url,
      source: article.source,
      content: article.content,
      description: article.description,
      published_at: article.published_at
    }
  end

  defp assert_eventually(fun, attempts \\ 30)
  defp assert_eventually(fun, 0), do: assert(fun.())

  defp assert_eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp slug(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end
end
