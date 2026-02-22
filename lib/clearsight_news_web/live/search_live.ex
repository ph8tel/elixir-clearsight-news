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
            <span class="truncate"><%= @article.source %></span>
            <span :if={@formatted_date} class="shrink-0 text-base-content/40">· {@formatted_date}</span>
          </div>
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
        <div class="flex flex-wrap items-center gap-1 text-xs text-base-content/40 mt-auto">
          <span class="font-mono">Score: <%= format_score(Map.get(@article, :computed_score)) %></span>
          <span :if={@emotion} class="badge badge-xs badge-ghost">
            <%= elem(@emotion, 1) %> <%= elem(@emotion, 0) %>
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

  defp format_date(nil), do: nil

  defp format_date(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 3_600 -> "#{max(div(diff, 60), 1)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> Calendar.strftime(dt, "%b %d")
    end
  end

  defp dominant_emotion(nil), do: nil

  defp dominant_emotion(computed_result) do
    emotions =
      Map.get(computed_result, :emotions) ||
        Map.get(computed_result, "emotions") ||
        %{}

    if map_size(emotions) > 0 do
      {name, score} = Enum.max_by(emotions, fn {_k, v} -> v || 0.0 end)
      if score > 0.15, do: {to_string(name), emotion_emoji(to_string(name))}
    end
  end

  defp emotion_emoji("joy"), do: "😊"
  defp emotion_emoji("trust"), do: "🤝"
  defp emotion_emoji("fear"), do: "😨"
  defp emotion_emoji("anger"), do: "😠"
  defp emotion_emoji("sadness"), do: "😢"
  defp emotion_emoji("anticipation"), do: "🔮"
  defp emotion_emoji("disgust"), do: "🤢"
  defp emotion_emoji("surprise"), do: "😲"
  defp emotion_emoji(_), do: "💬"

  defp loaded_language_high?(nil), do: false

  defp loaded_language_high?(computed_result) do
    ll =
      Map.get(computed_result, :loaded_language) ||
        Map.get(computed_result, "loaded_language") ||
        0.0

    ll > 0.4
  end

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
