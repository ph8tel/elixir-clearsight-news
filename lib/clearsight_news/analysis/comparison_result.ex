defmodule ClearsightNews.Analysis.ComparisonResult do
  @moduledoc """
  Instructor-backed schema for comparing two news articles on the same topic.

  Surfaces framing differences, tone contrast, source selection choices,
  factual gaps, and a relative bias assessment.
  """
  use Ecto.Schema
  use Instructor
  import Ecto.Changeset

  @llm_doc """
  Compare two news articles covering the same or similar topic.

  Return a JSON object with these fields:
  - framing_differences: string describing how each article frames the story
    differently — emphasis, angle, narrative choices
  - tone_comparison: string comparing the emotional appeal and tone of each article
  - source_selection: string noting differences in sources cited, experts quoted,
    or perspectives included or excluded
  - key_differences: string describing facts, angles, or context that one article
    includes and the other omits
  - bias_assessment: string giving a balanced assessment of which article appears
    more neutral and why, without taking a political position
  """

  @primary_key false
  embedded_schema do
    field :framing_differences, :string
    field :tone_comparison, :string
    field :source_selection, :string
    field :key_differences, :string
    field :bias_assessment, :string
  end

  @impl true
  def validate_changeset(changeset) do
    validate_required(changeset, [
      :framing_differences,
      :tone_comparison,
      :source_selection,
      :key_differences,
      :bias_assessment
    ])
  end
end
