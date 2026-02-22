defmodule ClearsightNewsWeb.ResultsLiveTest do
  use ClearsightNewsWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mox

  setup :verify_on_exit!

  test "GET /results without query redirects home", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/results")
  end

  test "GET /results renders columns with loading state", %{conn: conn} do
    ClearsightNews.MockNewsApi
    |> expect(:search, fn _query, _opts -> {:ok, []} end)

    {:ok, _view, html} = live(conn, ~p"/results?q=test")
    # Page title and query present
    assert html =~ "test"
    # Three column headings rendered
    assert html =~ "Positive"
    assert html =~ "Neutral"
    assert html =~ "Negative"
  end
end
