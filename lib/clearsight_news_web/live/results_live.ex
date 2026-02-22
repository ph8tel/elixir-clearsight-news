defmodule ClearsightNewsWeb.ResultsLive do
  use ClearsightNewsWeb, :live_view

  alias ClearsightNews.{Article, Analysis, ModelResponse, Repo, NewsApiService}

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
        <p class="text-xs text-base-content/50"><%= @article.source %></p>
        <p :if={@article.description} class="text-xs text-base-content/70 line-clamp-2">
          <%= @article.description %>
        </p>
        <div class="text-xs text-base-content/50 mt-1">
          Score: <span class="font-mono"><%= format_score(@article.computed_score) %></span>
        </div>
        <div class="card-actions mt-2 flex gap-1">
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

  # ---------------------------------------------------------------------------
  # Async work
  # ---------------------------------------------------------------------------

  defp fetch_and_analyse(query) do
    impl = NewsApiService.impl()

    with {:ok, raw_articles} <- impl.search(query, max: 15) do
      # Upsert articles — on_conflict :nothing keeps existing rows intact
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      rows =
        Enum.map(raw_articles, fn a ->
          Map.merge(a, %{inserted_at: now, updated_at: now})
        end)

      {_count, articles} =
        Repo.insert_all(Article, rows,
          on_conflict: {:replace, [:title, :content, :description, :updated_at]},
          conflict_target: :url,
          returning: true
        )

      # Run sentiment for each article, patch ModelResponse rows
      analysed =
        articles
        |> Task.async_stream(&run_sentiment/1,
          max_concurrency: 5,
          timeout: 30_000,
          on_timeout: :kill_task
        )
        |> Enum.zip(articles)
        |> Enum.map(fn
          {{:ok, article_with_score}, _} -> article_with_score
          {{:exit, _}, article} -> Map.put(article, :computed_score, nil)
        end)

      # Partition into three columns
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

  defp run_sentiment(article) do
    model_name = System.get_env("GROQ_SENTIMENT_MODEL", "llama-3.1-8b-instant")
    text = article.content || article.description || ""

    # Insert a pending response row
    {:ok, response} =
      %ModelResponse{}
      |> ModelResponse.changeset(%{
        article_id: article.id,
        response_type: "sentiment",
        model_name: model_name,
        status: "pending"
      })
      |> Repo.insert()

    start = System.monotonic_time(:millisecond)

    {status, computed_score, computed_result, error_message} =
      case Analysis.analyse_sentiment(text) do
        {:ok, result} ->
          score = Analysis.compute_sentiment_score(result)
          result_map = deep_struct_to_map(result)
          {"complete", score, result_map, nil}

        {:error, reason} ->
          {"error", nil, nil, inspect(reason)}
      end

    latency_ms = System.monotonic_time(:millisecond) - start

    # Patch the response row with results
    response
    |> ModelResponse.complete_changeset(%{
      status: status,
      latency_ms: latency_ms,
      computed_score: computed_score,
      computed_result: computed_result,
      error_message: error_message
    })
    |> Repo.update!()

    Map.put(article, :computed_score, computed_score)
  end

  defp deep_struct_to_map(%_struct{} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.map(fn {k, v} -> {k, deep_struct_to_map(v)} end)
    |> Enum.into(%{})
  end
  defp deep_struct_to_map([head | tail]), do: [deep_struct_to_map(head) | deep_struct_to_map(tail)]
  defp deep_struct_to_map(nil), do: nil
  defp deep_struct_to_map(value), do: value
end
