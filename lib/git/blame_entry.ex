defmodule Git.BlameEntry do
  @moduledoc """
  Struct representing a single parsed git blame entry.

  Each entry corresponds to one line of output from `git blame --porcelain`,
  containing the commit SHA, author information, line numbers, and the
  actual line content.
  """

  @type t :: %__MODULE__{
          commit: String.t(),
          author_name: String.t(),
          author_email: String.t(),
          author_time: String.t(),
          line_number: non_neg_integer(),
          original_line_number: non_neg_integer(),
          content: String.t()
        }

  defstruct [
    :commit,
    :author_name,
    :author_email,
    :author_time,
    :content,
    line_number: 0,
    original_line_number: 0
  ]
end
