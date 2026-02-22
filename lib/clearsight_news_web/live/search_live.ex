defmodule ClearsightNewsWeb.SearchLive do
  use ClearsightNewsWeb, :live_view

  alias ClearsightNews.{Analysis, ArticleAnalyzer, NewsApiService}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(query: "", page_title: "ClearSight News")
      |> assign(headlines: :loading)

    if connected?(socket) do
      send(self(), :fetch_headlines)
    end

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    q = String.trim(query)

    if q == "" do
      {:noreply, put_flash(socket, :error, "Please enter a search term.")}
    else
      {:noreply, push_navigate(socket, to: ~p"/results?q=#{q}")}
    end
  end

  # ---------------------------------------------------------------------------
  # Messages
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(:fetch_headlines, socket) do
    lv = self()

    {:ok, task_pid} =
      Task.Supervisor.start_child(ClearsightNews.TaskSupervisor, fn ->
        impl = NewsApiService.impl()

        case impl.top_headlines(max: 9) do
          {:ok, raw_articles} ->
            case ArticleAnalyzer.upsert_articles(raw_articles) do
              {:ok, articles} -> send(lv, {:headlines_ready, articles})
              _ -> send(lv, :headlines_failed)
            end

          _ ->
            send(lv, :headlines_failed)
        end
      end)

    ArticleAnalyzer.allow_sandbox(task_pid)
    {:noreply, socket}
  end

  def handle_info({:headlines_ready, articles}, socket) do
    # Build id→article map for O(1) patch updates
    articles_map = Map.new(articles, &{&1.id, &1})

    socket = assign(socket, headlines: articles_map)

    # Kick off sequential analysis only for pending articles
    pending = Enum.filter(articles, &(&1.analysis_status == "pending"))
    schedule_next_analysis(pending)

    {:noreply, socket}
  end

  def handle_info(:headlines_failed, socket) do
    {:noreply, assign(socket, headlines: :error)}
  end

  def handle_info({:analyse_article, article}, socket) do
    lv = self()

    {:ok, task_pid} =
      Task.Supervisor.start_child(ClearsightNews.TaskSupervisor, fn ->
        result = ArticleAnalyzer.run_sentiment(article)
        send(lv, {:analysis_result, result})
      end)

    ArticleAnalyzer.allow_sandbox(task_pid)
    {:noreply, socket}
  end

  def handle_info({:analysis_result, article}, socket) do
    socket =
      case socket.assigns.headlines do
        map when is_map(map) ->
          assign(socket, headlines: Map.put(map, article.id, article))

        other ->
          assign(socket, headlines: other)
      end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

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

          <%= cond do %>
            <% @headlines == :loading -> %>
              <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div :for={_ <- 1..9} class="card bg-base-200 h-44 animate-pulse" />
              </div>
            <% @headlines == :error -> %>
              <p class="text-error">Could not load latest articles.</p>
            <% true -> %>
              <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                <.headline_card
                  :for={{_id, article} <- @headlines}
                  article={article}
                />
              </div>
          <% end %>
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
    computed_result = Map.get(assigns.article, :computed_result)

    assigns =
      assigns
      |> assign(:formatted_date, format_date(assigns.article.published_at))
      |> assign(:emotion, dominant_emotion(computed_result))
      |> assign(:loaded_lang_high, loaded_language_high?(computed_result))

    ~H"""
    <div class="card bg-base-100 shadow border-2 border-transparent hover:border-primary transition-colors h-full">
      <div class="card-body p-4 flex flex-col gap-2">
        <div class="flex items-center justify-between gap-2">
          <div class="flex items-center gap-1 text-xs text-base-content/50 min-w-0">
            <span class="truncate">{@article.source}</span>
            <span :if={@formatted_date} class="shrink-0 text-base-content/40">
              · {@formatted_date}
            </span>
          </div>
          <%= if is_nil(Map.get(@article, :computed_score)) do %>
            <span class={[
              "badge badge-sm shrink-0",
              sentiment_badge_class(Map.get(@article, :analysis_status))
            ]}>
              {sentiment_label(Map.get(@article, :analysis_status))}
            </span>
          <% else %>
            <span class={["badge badge-sm shrink-0", sentiment_badge_class(@article.computed_score)]}>
              {sentiment_label(@article.computed_score)}
            </span>
          <% end %>
        </div>
        <h3 class="font-semibold text-sm leading-snug">
          <a href={@article.url} target="_blank" rel="noopener" class="hover:underline">
            {@article.title}
          </a>
        </h3>
        <p :if={@article.description} class="text-xs text-base-content/70 line-clamp-3 flex-1">
          {@article.description}
        </p>
        <div class="flex flex-wrap items-center gap-1 text-xs text-base-content/40 mt-auto">
          <span class="font-mono">Score: {format_score(Map.get(@article, :computed_score))}</span>
          <span :if={@emotion} class="badge badge-xs badge-ghost">
            {elem(@emotion, 1)} {elem(@emotion, 0)}
          </span>
          <span :if={@loaded_lang_high} class="badge badge-xs badge-warning">🔥 loaded</span>
        </div>
        <a
          href={@article.url}
          target="_blank"
          rel="noopener"
          class="btn btn-xs btn-outline btn-primary w-full mt-1"
        >
          Read article ↗
        </a>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp sentiment_badge_class("pending"), do: "badge-neutral animate-pulse"
  defp sentiment_badge_class(nil), do: "badge-neutral"

  defp sentiment_badge_class(score) do
    case Analysis.classify(score) do
      :positive -> "badge-success"
      :negative -> "badge-error"
      :neutral -> "badge-ghost"
    end
  end

  defp sentiment_label("pending"), do: "Analyzing…"
  defp sentiment_label(nil), do: "Unscored"
  defp sentiment_label(score), do: Analysis.label(score)
end
