defmodule ClearsightNewsWeb.ResultsLive do
  use ClearsightNewsWeb, :live_view

  alias ClearsightNews.{Analysis, ArticleAnalyzer, NewsApiService}

  @mobile_sentiment_tabs ["positive", "neutral", "negative"]

  @impl true
  def mount(%{"q" => query}, _session, socket) do
    q = String.trim(query)

    socket =
      socket
      |> assign(query: q, page_title: "#{q} · ClearSight")
      |> assign(primary: nil, reference: nil)
      |> assign(active_sentiment_tab: "positive")
      |> assign(articles: :loading, fetch_error: nil)

    if connected?(socket) do
      send(self(), :fetch_articles)
    end

    {:ok, socket}
  end

  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/")}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("select_primary", %{"id" => id}, socket) do
    {:noreply, assign(socket, primary: String.to_integer(id))}
  end

  def handle_event("select_reference", %{"id" => id}, socket) do
    {:noreply, assign(socket, reference: String.to_integer(id))}
  end

  def handle_event("compare", _params, socket) do
    %{primary: p, reference: r} = socket.assigns

    if p && r && p != r do
      {:noreply, push_navigate(socket, to: ~p"/compare?primary=#{p}&reference=#{r}")}
    else
      {:noreply, put_flash(socket, :error, "Select two different articles to compare.")}
    end
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in @mobile_sentiment_tabs do
    {:noreply, assign(socket, active_sentiment_tab: tab)}
  end

  def handle_event("switch_tab", _params, socket) do
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Messages
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(:fetch_articles, socket) do
    lv = self()
    q = socket.assigns.query

    {:ok, task_pid} =
      Task.Supervisor.start_child(ClearsightNews.TaskSupervisor, fn ->
        impl = NewsApiService.impl()

        case impl.search(q, max: 15) do
          {:ok, raw_articles} ->
            case ArticleAnalyzer.upsert_articles(raw_articles) do
              {:ok, articles} -> send(lv, {:articles_ready, articles})
              _ -> send(lv, {:fetch_failed, "DB error"})
            end

          {:error, reason} ->
            send(lv, {:fetch_failed, reason})
        end
      end)

    ArticleAnalyzer.allow_sandbox(task_pid)
    {:noreply, socket}
  end

  def handle_info({:articles_ready, articles}, socket) do
    articles_map = Map.new(articles, &{&1.id, &1})
    pending = Enum.filter(articles, &(&1.analysis_status == "pending"))
    schedule_next_analysis(pending)
    {:noreply, assign(socket, articles: articles_map)}
  end

  def handle_info({:fetch_failed, reason}, socket) do
    {:noreply, assign(socket, articles: :error, fetch_error: reason)}
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
      case socket.assigns.articles do
        map when is_map(map) ->
          assign(socket, articles: Map.put(map, article.id, article))

        other ->
          assign(socket, articles: other)
      end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    # Build sorted columns from the id→article map whenever it's available.
    # Pending articles go into :neutral temporarily so they appear immediately.
    assigns =
      case assigns.articles do
        map when is_map(map) ->
          articles = Map.values(map)

          columns =
            Enum.group_by(articles, fn a ->
              case a.computed_score do
                nil -> :neutral
                s -> Analysis.classify(s)
              end
            end)

          assign(assigns,
            col_positive: Map.get(columns, :positive, []),
            col_neutral: Map.get(columns, :neutral, []),
            col_negative: Map.get(columns, :negative, [])
          )

        _ ->
          assign(assigns, col_positive: [], col_neutral: [], col_negative: [])
      end

    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <%!-- Header --%>
      <div class="mb-8 space-y-3">
        <div class="space-y-2 md:flex md:items-start md:justify-between md:gap-6 md:space-y-0">
          <h1 id="results-title" class="text-2xl font-bold">Results for: "{@query}"</h1>
          <p class="text-sm text-base-content/70 md:max-w-xl md:text-right">
            Select a primary and reference article to compare their rhetoric.
          </p>
        </div>

        <div id="results-header-actions" class="flex flex-wrap items-center gap-2 md:justify-between">
          <.link navigate={~p"/"} class="btn btn-ghost btn-sm">← Back</.link>
          <button
            :if={@primary && @reference}
            phx-click="compare"
            class="btn btn-primary btn-sm md:btn-md"
          >
            Compare Selected
          </button>
        </div>
      </div>

      <%= cond do %>
        <% @articles == :loading -> %>
          <div class="md:hidden">
            <.mobile_tabs
              active_tab={@active_sentiment_tab}
              positive_count={0}
              neutral_count={0}
              negative_count={0}
            />
            <div id="mobile-active-column" role="tabpanel" class="mt-4">
              <.column_skeleton label={tab_label(@active_sentiment_tab)} />
            </div>
          </div>

          <div class="hidden md:grid md:grid-cols-3 gap-6">
            <.column_skeleton label="Positive" />
            <.column_skeleton label="Neutral" />
            <.column_skeleton label="Negative" />
          </div>
        <% @articles == :error -> %>
          <div class="alert alert-error">
            Failed to load articles. Please try again.
          </div>
        <% true -> %>
          <div class="md:hidden">
            <.mobile_tabs
              active_tab={@active_sentiment_tab}
              positive_count={length(@col_positive)}
              neutral_count={length(@col_neutral)}
              negative_count={length(@col_negative)}
            />
            <div id="mobile-active-column" role="tabpanel" class="mt-4">
              <%= case @active_sentiment_tab do %>
                <% "positive" -> %>
                  <.column
                    label="Positive"
                    articles={@col_positive}
                    primary={@primary}
                    reference={@reference}
                  />
                <% "negative" -> %>
                  <.column
                    label="Negative"
                    articles={@col_negative}
                    primary={@primary}
                    reference={@reference}
                  />
                <% _ -> %>
                  <.column
                    label="Neutral"
                    articles={@col_neutral}
                    primary={@primary}
                    reference={@reference}
                  />
              <% end %>
            </div>
          </div>

          <div class="hidden md:grid md:grid-cols-3 gap-6">
            <.column
              label="Positive"
              articles={@col_positive}
              primary={@primary}
              reference={@reference}
            />
            <.column
              label="Neutral"
              articles={@col_neutral}
              primary={@primary}
              reference={@reference}
            />
            <.column
              label="Negative"
              articles={@col_negative}
              primary={@primary}
              reference={@reference}
            />
          </div>
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  attr :label, :string, required: true
  attr :articles, :list, default: []
  attr :primary, :any, default: nil
  attr :reference, :any, default: nil

  defp column(assigns) do
    ~H"""
    <div>
      <h2 class={["text-lg font-semibold mb-3 text-center", label_class(@label)]}>
        {@label} ({length(@articles)})
      </h2>
      <div :if={@articles == []} class="text-center text-base-content/40 text-sm py-8">
        No articles
      </div>
      <.article_card
        :for={article <- @articles}
        article={article}
        is_primary={@primary == article.id}
        is_reference={@reference == article.id}
      />
    </div>
    """
  end

  attr :label, :string, required: true

  defp column_skeleton(assigns) do
    ~H"""
    <div>
      <h2 class={["text-lg font-semibold mb-3 text-center animate-pulse", label_class(@label)]}>
        {@label}
      </h2>
      <div :for={_ <- 1..3} class="card bg-base-200 mb-3 h-32 animate-pulse" />
    </div>
    """
  end

  attr :active_tab, :string, required: true
  attr :positive_count, :integer, required: true
  attr :neutral_count, :integer, required: true
  attr :negative_count, :integer, required: true

  defp mobile_tabs(assigns) do
    ~H"""
    <div
      id="results-mobile-tabs"
      role="tablist"
      aria-label="Sentiment tabs"
      class="tabs tabs-boxed w-full"
    >
      <button
        id="tab-positive"
        role="tab"
        type="button"
        phx-click="switch_tab"
        phx-value-tab="positive"
        aria-selected={@active_tab == "positive"}
        class={[
          "tab flex-1",
          @active_tab == "positive" && "tab-active text-success"
        ]}
      >
        Positive <span class="badge badge-sm ml-1">{@positive_count}</span>
      </button>
      <button
        id="tab-neutral"
        role="tab"
        type="button"
        phx-click="switch_tab"
        phx-value-tab="neutral"
        aria-selected={@active_tab == "neutral"}
        class={[
          "tab flex-1",
          @active_tab == "neutral" && "tab-active"
        ]}
      >
        Neutral <span class="badge badge-sm ml-1">{@neutral_count}</span>
      </button>
      <button
        id="tab-negative"
        role="tab"
        type="button"
        phx-click="switch_tab"
        phx-value-tab="negative"
        aria-selected={@active_tab == "negative"}
        class={[
          "tab flex-1",
          @active_tab == "negative" && "tab-active text-error"
        ]}
      >
        Negative <span class="badge badge-sm ml-1">{@negative_count}</span>
      </button>
    </div>
    """
  end

  attr :article, :map, required: true
  attr :is_primary, :boolean, default: false
  attr :is_reference, :boolean, default: false

  defp article_card(assigns) do
    computed_result = Map.get(assigns.article, :computed_result)
    status = Map.get(assigns.article, :analysis_status)

    assigns =
      assigns
      |> assign(:formatted_date, format_date(assigns.article.published_at))
      |> assign(:emotion, dominant_emotion(computed_result))
      |> assign(:loaded_lang_high, loaded_language_high?(computed_result))
      |> assign(:has_error, status == "error")
      |> assign(:pending, status == "pending")

    ~H"""
    <div class={[
      "card bg-base-100 shadow mb-3 border-2 transition-colors",
      @is_primary && "border-primary",
      @is_reference && "border-secondary",
      !@is_primary && !@is_reference && "border-transparent"
    ]}>
      <div class="card-body p-4">
        <h3 class="card-title text-sm leading-snug">
          <a href={@article.url} target="_blank" rel="noopener" class="hover:underline">
            {@article.title}
          </a>
        </h3>
        <div class="flex items-center gap-1 text-xs text-base-content/50">
          <span>{@article.source}</span>
          <span :if={@formatted_date} class="text-base-content/40">· {@formatted_date}</span>
        </div>
        <p :if={@article.description} class="text-xs text-base-content/70 line-clamp-2">
          {@article.description}
        </p>
        <div class="flex flex-wrap items-center gap-1 text-xs text-base-content/50 mt-1">
          <%= if @pending do %>
            <span class="badge badge-xs badge-neutral animate-pulse">Analyzing…</span>
          <% else %>
            <span>
              Score: <span class="font-mono">{format_score(Map.get(@article, :computed_score))}</span>
            </span>
            <span :if={@emotion} class="badge badge-xs badge-ghost">
              {elem(@emotion, 1)} {elem(@emotion, 0)}
            </span>
            <span :if={@loaded_lang_high} class="badge badge-xs badge-warning">
              🔥 loaded language
            </span>
            <span :if={@has_error} class="badge badge-xs badge-error">analysis error</span>
          <% end %>
        </div>
        <div class="card-actions mt-2 flex flex-wrap gap-1">
          <button
            phx-click="select_primary"
            phx-value-id={@article.id}
            class={["btn btn-xs", @is_primary && "btn-primary", !@is_primary && "btn-outline"]}
          >
            {if @is_primary, do: "✓ Primary", else: "Set Primary"}
          </button>
          <button
            phx-click="select_reference"
            phx-value-id={@article.id}
            class={["btn btn-xs", @is_reference && "btn-secondary", !@is_reference && "btn-outline"]}
          >
            {if @is_reference, do: "✓ Reference", else: "Set Reference"}
          </button>
          <a
            href={@article.url}
            target="_blank"
            rel="noopener"
            class="btn btn-xs btn-ghost ml-auto"
          >
            Read article ↗
          </a>
        </div>
      </div>
    </div>
    """
  end

  defp label_class("Positive"), do: "text-success"
  defp label_class("Negative"), do: "text-error"
  defp label_class(_), do: "text-base-content"

  defp tab_label("positive"), do: "Positive"
  defp tab_label("negative"), do: "Negative"
  defp tab_label(_), do: "Neutral"
end
