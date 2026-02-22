defmodule ClearsightNewsWeb.SearchLive do
  use ClearsightNewsWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, query: "", page_title: "ClearSight News")}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    q = String.trim(query)

    if q == "" do
      {:noreply, put_flash(socket, :error, "Please enter a search term.")}
    else
      {:noreply, push_navigate(socket, to: ~p"/results?q=#{q}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col items-center justify-center px-4">
      <.flash kind={:error} flash={@flash} />
      <.flash kind={:info} flash={@flash} />
      <div class="w-full max-w-2xl">
        <h1 class="text-4xl font-bold text-center mb-2">ClearSight News</h1>
        <p class="text-center text-base-content/60 mb-10">
          Search any topic. See how articles compare by sentiment.
        </p>

        <.form for={%{}} as={:search} phx-submit="search" class="flex gap-2">
          <input
            type="text"
            name="search[query]"
            value={@query}
            placeholder="e.g. climate policy, inflation, election..."
            class="input input-bordered flex-1 text-lg"
            autofocus
          />
          <button type="submit" class="btn btn-primary px-6">Search</button>
        </.form>
      </div>
    </div>
    """
  end
end
