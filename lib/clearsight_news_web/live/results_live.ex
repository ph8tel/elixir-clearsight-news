defmodule ClearsightNewsWeb.ResultsLive do
  use ClearsightNewsWeb, :live_view

  alias ClearsightNews.{Analysis, ArticleAnalyzer, NewsApiService}

  @impl true
  def mount(%{"q" => query}, _session, socket) do
    q = String.trim(query)

    socket =
      socket
      |> assign(query: q, page_title: "#{q} · ClearSight")
      |> assign(primary: nil, reference: nil)
      |> assign_async(:results, fn ->
        case fetch_and_analyse(q) do
          {:ok, columns} -> {:ok, %{results: columns}}
          {:error, reason} -> {:error, reason}
        end
      end,
        supervisor: ClearsightNews.TaskSupervisor
      )

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

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <%!-- Header --%>
      <div class="flex items-center gap-4 mb-8">
        <.link navigate={~p"/"} class="btn btn-ghost btn-sm">← Back</.link>
        <h1 class="text-2xl font-bold flex-1">Results for "<%= @query %>"</h1>
        <button
          :if={@primary && @reference}
          phx-click="compare"
          class="btn btn-primary"
        >
          Compare Selected
        </button>
      </div>

      <.async_result :let={columns} assign={@results}>
        <:loading>
          <div class="grid grid-cols-3 gap-6">
            <.column_skeleton label="Positive" />
            <.column_skeleton label="Neutral" />
            <.column_skeleton label="Negative" />
          </div>
        </:loading>

        <:failed :let={_reason}>
          <div class="alert alert-error">
            Failed to load articles. Please try again.
          </div>
        </:failed>

        <div class="grid grid-cols-3 gap-6">
          <.column
            label="Positive"
            articles={columns.positive}
            primary={@primary}
            reference={@reference}
          />
          <.column
            label="Neutral"
            articles={columns.neutral}
            primary={@primary}
            reference={@reference}
          />
          <.column
            label="Negative"
            articles={columns.negative}
            primary={@primary}
            reference={@reference}
          />
        </div>
      </.async_result>
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
        <%= @label %> (<%= length(@articles) %>)
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
        <%= @label %>
      </h2>
      <div :for={_ <- 1..3} class="card bg-base-200 mb-3 h-32 animate-pulse" />
    </div>
    """
  end

  attr :article, :map, required: true
  attr :is_primary, :boolean, default: false
  attr :is_reference, :boolean, default: false

  defp article_card(assigns) do
    computed_result = Map.get(assigns.article, :computed_result)

    assigns =
      assigns
      |> assign(:formatted_date, format_date(assigns.article.published_at))
      |> assign(:emotion, dominant_emotion(computed_result))
      |> assign(:loaded_lang_high, loaded_language_high?(computed_result))
      |> assign(:has_error, Map.get(assigns.article, :analysis_status) == "error")

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
            <%= @article.title %>
          </a>
        </h3>
        <div class="flex items-center gap-1 text-xs text-base-content/50">
          <span><%= @article.source %></span>
          <span :if={@formatted_date} class="text-base-content/40">· {@formatted_date}</span>
        </div>
        <p :if={@article.description} class="text-xs text-base-content/70 line-clamp-2">
          <%= @article.description %>
        </p>
        <div class="flex flex-wrap items-center gap-1 text-xs text-base-content/50 mt-1">
          <span>Score: <span class="font-mono"><%= format_score(Map.get(@article, :computed_score)) %></span></span>
          <span :if={@emotion} class="badge badge-xs badge-ghost">
            <%= elem(@emotion, 1) %> <%= elem(@emotion, 0) %>
          </span>
          <span :if={@loaded_lang_high} class="badge badge-xs badge-warning">🔥 loaded language</span>
          <span :if={@has_error} class="badge badge-xs badge-error">analysis error</span>
        </div>
        <div class="card-actions mt-2 flex flex-wrap gap-1">
          <button
            phx-click="select_primary"
            phx-value-id={@article.id}
            class={["btn btn-xs", @is_primary && "btn-primary", !@is_primary && "btn-outline"]}
          >
            <%= if @is_primary, do: "✓ Primary", else: "Set Primary" %>
          </button>
          <button
            phx-click="select_reference"
            phx-value-id={@article.id}
            class={["btn btn-xs", @is_reference && "btn-secondary", !@is_reference && "btn-outline"]}
          >
            <%= if @is_reference, do: "✓ Reference", else: "Set Reference" %>
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

  defp fetch_and_analyse(query) do
    impl = NewsApiService.impl()

    with {:ok, raw_articles} <- impl.search(query, max: 15),
         {:ok, analysed} <- ArticleAnalyzer.upsert_and_analyse(raw_articles) do
      columns =
        Enum.group_by(analysed, fn a ->
          case a.computed_score do
            nil -> :neutral
            s -> Analysis.classify(s)
          end
        end)

      {:ok,
       %{
         positive: Map.get(columns, :positive, []),
         neutral: Map.get(columns, :neutral, []),
         negative: Map.get(columns, :negative, [])
       }}
    end
  end
end
