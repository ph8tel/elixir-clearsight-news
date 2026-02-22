defmodule ClearsightNewsWeb.SearchLiveTest do
  use ClearsightNewsWeb.ConnCase

  import Phoenix.LiveViewTest

  test "GET / renders search form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "ClearSight News"
    assert html =~ "Search"
  end

  test "submitting empty query shows error", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("form", search: %{query: "   "})
    |> render_submit()

    assert render(view) =~ "Please enter a search term"
  end

  test "submitting a query navigates to results", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert {:error, {:live_redirect, %{to: "/results?q=climate"}}} =
             view
             |> form("form", search: %{query: "climate"})
             |> render_submit()
  end
end
