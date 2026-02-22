defmodule ClearsightNewsWeb.SearchLive do
  use ClearsightNewsWeb, :live_view

  alias ClearsightNews.{Analysis, ArticleAnalyzer, NewsApiService}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(query: "", page_title: "ClearSight News")
      |> assign_async(:latest, fn -> fetch_latest() end,
        supervisor: ClearsightNews.TaskSupervisor
      )

    {:ok, socket}
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
    <div class="min-h-screen px-4 py-12">
      <.flash kind={:error} flash={@flash} />
      <.flash kind={:info} flash={@flash} />

      <div class="max-w-7xl mx-auto">
        <%!-- Search bar --%>
        <div class="flex flex-col items-center mb-14">
          <h1 class="text-4xl font-bold text-center mb-2">ClearSight News</h1>
          <p class="text-center text-base-content/60 mb-10">
            Search any topic. See how articles compare by sentiment.
          </p>
          <.form for={%{}} as={:search} phx-submit="search" class="flex gap-2 w-full max-w-2xl">
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

        <%!-- Latest headlines grid --%>
        <div>
          <h2 class="text-xl font-semibold mb-6">Latest Headlines</h2>

          <.async_result :let={articles} assign={@latest}>
            <:loading>
              <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div :for={_ <- 1..9} class="card bg-base-200 h-44 animate-pulse" />
              </div>
            </:loading>
            <:failed :let={_reason}>
              <p class="text-error">Could not load latest articles.</p>
            </:failed>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <.headline_card :for={article <- articles} article={article} />
            </div>
          </.async_result>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  attr :article, :map, required: true

  defp headline_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow border-2 border-transparent hover:border-primary transition-colors">
      <div class="card-body p-4 flex flex-col gap-2">
        <div class="flex items-center justify-between gap-2">
          <span class="text-xs text-base-content/50 truncate"><%= @article.source %></span>
          <span class={["badge badge-sm shrink-0", sentiment_badge_class(@article.computed_score)]}>
            <%= sentiment_label(@article.computed_score) %>
          </span>
        </div>
        <h3 class="font-semibold text-sm leading-snug">
          <a href={@article.url} target="_blank" rel="noopener" class="hover:underline">
            <%= @article.title %>
          </a>
        </h3>
        <p :if={@article.description} class="text-xs text-base-content/70 line-clamp-3 flex-1">
          <%= @article.description %>
        </p>
        <div class="text-xs text-base-content/40 font-mono mt-auto">
          Score: <%= format_score(@article.computed_score) %>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp sentiment_badge_class(nil), do: "badge-ghost"

  defp sentiment_badge_class(score) do
    case Analysis.classify(score) do
      :positive -> "badge-success"
      :negative -> "badge-error"
      :neutral -> "badge-ghost"
    end
  end

  defp sentiment_label(nil), do: "—"
  defp sentiment_label(score), do: Analysis.label(score)

  defp format_score(nil), do: "—"
  defp format_score(score), do: :erlang.float_to_binary(score, decimals: 3)

  # ---------------------------------------------------------------------------
  # Async work
  # ---------------------------------------------------------------------------

  defp fetch_latest do
    impl = NewsApiService.impl()

    with {:ok, raw_articles} <- impl.top_headlines(max: 9),
         {:ok, analysed} <- ArticleAnalyzer.upsert_and_analyse(raw_articles) do
      {:ok, %{latest: analysed}}
    end
  end
end
