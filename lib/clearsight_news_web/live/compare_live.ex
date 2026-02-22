defmodule ClearsightNewsWeb.CompareLive do
  use ClearsightNewsWeb, :live_view

  alias ClearsightNews.{Article, Analysis, ArticleAnalyzer, ModelResponse, Repo}

  @impl true
  def mount(%{"primary" => p_id, "reference" => r_id}, _session, socket) do
    primary = Repo.get(Article, p_id)
    reference = Repo.get(Article, r_id)

    if is_nil(primary) or is_nil(reference) do
      {:ok,
       socket
       |> put_flash(:error, "One or both articles not found.")
       |> push_navigate(to: ~p"/")}
    else
      socket =
        socket
        |> assign(primary: primary, reference: reference)
        |> assign(page_title: "Compare · ClearSight")
        |> assign_async(
          :primary_rhetoric,
          fn ->
            case run_rhetoric(primary) do
              {:ok, value} -> {:ok, %{primary_rhetoric: value}}
              {:error, reason} -> {:error, reason}
            end
          end,
          supervisor: ClearsightNews.TaskSupervisor
        )
        |> assign_async(
          :reference_rhetoric,
          fn ->
            case run_rhetoric(reference) do
              {:ok, value} -> {:ok, %{reference_rhetoric: value}}
              {:error, reason} -> {:error, reason}
            end
          end,
          supervisor: ClearsightNews.TaskSupervisor
        )
        |> assign_async(
          :comparison,
          fn ->
            case run_comparison(primary, reference) do
              {:ok, value} -> {:ok, %{comparison: value}}
              {:error, reason} -> {:error, reason}
            end
          end,
          supervisor: ClearsightNews.TaskSupervisor
        )

      {:ok, socket}
    end
  end

  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/")}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="flex items-center gap-4 mb-8">
        <.link navigate={~p"/"} class="btn btn-ghost btn-sm">← New Search</.link>
        <h1 class="text-2xl font-bold">Article Comparison</h1>
      </div>

      <%!-- Side-by-side rhetoric --%>
      <div class="grid grid-cols-2 gap-6 mb-10">
        <.rhetoric_panel label="Primary" article={@primary} result={@primary_rhetoric} />
        <.rhetoric_panel label="Reference" article={@reference} result={@reference_rhetoric} />
      </div>

      <%!-- Comparison --%>
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title text-xl mb-4">Cross-Article Comparison</h2>
          <.async_result :let={comp} assign={@comparison}>
            <:loading>
              <div class="space-y-3">
                <div :for={_ <- 1..5} class="h-6 bg-base-200 rounded animate-pulse" />
              </div>
            </:loading>
            <:failed :let={_}>
              <p class="text-error">Comparison failed. Please try again.</p>
            </:failed>
            <.comparison_body result={comp.result} />
          </.async_result>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  attr :label, :string, required: true
  attr :article, Article, required: true
  # AsyncResult
  attr :result, :any, required: true

  defp rhetoric_panel(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow">
      <div class="card-body">
        <div class="text-xs font-semibold text-base-content/50 uppercase tracking-wide mb-1">
          {@label}
        </div>
        <h2 class="text-base font-bold leading-snug mb-1">
          <a href={@article.url} target="_blank" rel="noopener" class="hover:underline">
            {@article.title}
          </a>
        </h2>
        <p class="text-xs text-base-content/50 mb-4">{@article.source}</p>

        <.async_result :let={rh} assign={@result}>
          <:loading>
            <div class="space-y-2">
              <div :for={_ <- 1..4} class="h-4 bg-base-200 rounded animate-pulse" />
            </div>
          </:loading>
          <:failed :let={_}>
            <p class="text-error text-sm">Rhetoric analysis failed.</p>
          </:failed>
          <.rhetoric_body result={rh.result} />
        </.async_result>
      </div>
    </div>
    """
  end

  attr :result, :any, required: true

  defp rhetoric_body(%{result: nil} = assigns) do
    ~H(<p class="text-sm text-base-content/50">No result</p>)
  end

  defp rhetoric_body(assigns) do
    ~H"""
    <div class="space-y-3 text-sm">
      <div>
        <span class="font-semibold">Tone: </span>{@result.overall_tone}
        <span class={"ml-2 badge badge-sm #{sentiment_badge(@result.sentiment_label)}"}>
          {String.capitalize(@result.sentiment_label || "")}
        </span>
      </div>

      <div :if={@result.rhetorical_devices != []}>
        <p class="font-semibold mb-1">Rhetorical Devices</p>
        <ul class="list-disc list-inside space-y-1 text-xs text-base-content/80">
          <li :for={d <- @result.rhetorical_devices}>
            <span class="font-medium">{d.device}</span>
            <span :if={d.example} class="italic"> — "{d.example}"</span>
          </li>
        </ul>
      </div>

      <div :if={@result.bias_indicators != []}>
        <p class="font-semibold mb-1">Bias Indicators</p>
        <ul class="list-disc list-inside space-y-1 text-xs text-base-content/80">
          <li :for={b <- @result.bias_indicators}>{b}</li>
        </ul>
      </div>
    </div>
    """
  end

  attr :result, :any, required: true

  defp comparison_body(%{result: nil} = assigns) do
    ~H(<p class="text-sm text-base-content/50">No result</p>)
  end

  defp comparison_body(assigns) do
    ~H"""
    <dl class="space-y-5 text-sm">
      <.comp_field label="Framing Differences" value={@result.framing_differences} />
      <.comp_field label="Tone Comparison" value={@result.tone_comparison} />
      <.comp_field label="Source Selection" value={@result.source_selection} />
      <.comp_field label="Key Differences" value={@result.key_differences} />
      <.comp_field label="Bias Assessment" value={@result.bias_assessment} />
    </dl>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, default: nil

  defp comp_field(assigns) do
    ~H"""
    <div>
      <dt class="font-semibold text-base-content mb-1">{@label}</dt>
      <dd class="text-base-content/80 leading-relaxed">{@value || "—"}</dd>
    </div>
    """
  end

  defp sentiment_badge("positive"), do: "badge-success"
  defp sentiment_badge("negative"), do: "badge-error"
  defp sentiment_badge(_), do: "badge-ghost"

  # ---------------------------------------------------------------------------
  # Async work
  # ---------------------------------------------------------------------------

  defp run_rhetoric(article) do
    model_name = System.get_env("GROQ_RHETORIC_MODEL", "llama-3.3-70b-versatile")
    text = article.content || ""

    {:ok, response} =
      %ModelResponse{}
      |> ModelResponse.changeset(%{
        article_id: article.id,
        response_type: "rhetoric",
        model_name: model_name,
        status: "pending"
      })
      |> Repo.insert()

    start = System.monotonic_time(:millisecond)

    {status, result, error_message} =
      case Analysis.analyse_rhetoric(text) do
        {:ok, r} -> {"complete", r, nil}
        {:error, reason} -> {"error", nil, inspect(reason)}
      end

    latency_ms = System.monotonic_time(:millisecond) - start

    response
    |> ModelResponse.complete_changeset(%{
      status: status,
      latency_ms: latency_ms,
      computed_result: result && ArticleAnalyzer.deep_struct_to_map(result),
      error_message: error_message
    })
    |> Repo.update!()

    {:ok, %{result: result}}
  end

  defp run_comparison(primary, reference) do
    model_name = System.get_env("GROQ_COMPARISON_MODEL", "llama-3.3-70b-versatile")
    primary_text = primary.content || ""
    reference_text = reference.content || ""

    {:ok, response} =
      %ModelResponse{}
      |> ModelResponse.changeset(%{
        article_id: primary.id,
        reference_article_id: reference.id,
        response_type: "comparison",
        model_name: model_name,
        status: "pending"
      })
      |> Repo.insert()

    start = System.monotonic_time(:millisecond)

    {status, result, error_message} =
      case Analysis.analyse_comparison(primary_text, reference_text) do
        {:ok, r} -> {"complete", r, nil}
        {:error, reason} -> {"error", nil, inspect(reason)}
      end

    latency_ms = System.monotonic_time(:millisecond) - start

    response
    |> ModelResponse.complete_changeset(%{
      status: status,
      latency_ms: latency_ms,
      computed_result: result && ArticleAnalyzer.deep_struct_to_map(result),
      error_message: error_message
    })
    |> Repo.update!()

    {:ok, %{result: result}}
  end
end
