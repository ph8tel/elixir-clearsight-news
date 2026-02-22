defmodule ClearsightNewsWeb.ArticleHelpers do
  @moduledoc """
  Shared view helpers for article-related LiveViews.

  Imported automatically via `ClearsightNewsWeb.html_helpers/0`, so these
  functions are available in all LiveViews, LiveComponents, and HTML modules
  without an explicit import.
  """

  # Delay between sequential Groq calls (ms) to stay within rate limits.
  @analysis_interval 300

  @doc "Format a computed sentiment score for display, or \"—\" when absent."
  def format_score(nil), do: "—"
  def format_score(score), do: :erlang.float_to_binary(score, decimals: 3)

  @doc """
  Format a `DateTime` as a relative string ("5m ago", "3h ago") or a short
  date ("Feb 22") depending on how old it is. Returns `nil` for a nil input.
  """
  def format_date(nil), do: nil

  def format_date(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 3_600 -> "#{max(div(diff, 60), 1)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> Calendar.strftime(dt, "%b %d")
    end
  end

  @doc """
  Return `{emotion_name, emoji}` for the highest-scoring emotion in a
  `computed_result` map, provided it exceeds the display threshold (0.15).
  Returns `nil` when the result is absent or all emotions are below the
  threshold.
  """
  def dominant_emotion(nil), do: nil

  def dominant_emotion(computed_result) do
    emotions =
      Map.get(computed_result, :emotions) ||
        Map.get(computed_result, "emotions") ||
        %{}

    if map_size(emotions) > 0 do
      {name, score} = Enum.max_by(emotions, fn {_k, v} -> v || 0.0 end)
      if score > 0.15, do: {to_string(name), emotion_emoji(to_string(name))}
    end
  end

  @doc "Return `true` when the loaded-language score in a result map exceeds 0.4."
  def loaded_language_high?(nil), do: false

  def loaded_language_high?(computed_result) do
    ll =
      Map.get(computed_result, :loaded_language) ||
        Map.get(computed_result, "loaded_language") ||
        0.0

    ll > 0.4
  end

  @doc """
  Schedule per-article sentiment tasks spaced `@analysis_interval` ms apart.

  For each article in the list, this function sends
  `{:analyse_article, article}` to `self()` using `Process.send_after/3`.

  * When the list is empty (`[]`), no messages are scheduled and `:ok` is
    returned immediately.
  * When the list contains a single article, exactly one message is
    scheduled to run after `@analysis_interval` milliseconds.
  * For longer lists, the first article is scheduled after
    `@analysis_interval` milliseconds and each subsequent article is
    scheduled `@analysis_interval` milliseconds after the previous one,
    forming an evenly spaced sequence of analysis tasks.

  Must be called from a LiveView process (or a process that implements the
  corresponding `handle_info/2` callbacks) because the scheduled messages
  are delivered to `self()`. Calling this from a non-LiveView process that
  does not handle `{:analyse_article, article}` messages will result in the
  messages being sent to the wrong place, meaning analyses will never run
  and may cause unexpected mailbox growth or crashes if another `handle_info/2`
  later pattern-matches on these messages incorrectly.
  """
  def schedule_next_analysis([]), do: :ok

  def schedule_next_analysis([article | rest]) do
    interval = @analysis_interval

    Process.send_after(self(), {:analyse_article, article}, interval)

    Enum.reduce(rest, interval, fn article, delay ->
      new_delay = delay + interval
      Process.send_after(self(), {:analyse_article, article}, new_delay)
      new_delay
    end)
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp emotion_emoji("joy"), do: "😊"
  defp emotion_emoji("trust"), do: "🤝"
  defp emotion_emoji("fear"), do: "😨"
  defp emotion_emoji("anger"), do: "😠"
  defp emotion_emoji("sadness"), do: "😢"
  defp emotion_emoji("anticipation"), do: "🔮"
  defp emotion_emoji("disgust"), do: "🤢"
  defp emotion_emoji("surprise"), do: "😲"
  defp emotion_emoji(_), do: "💬"
end
