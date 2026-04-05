defmodule Git.GrepResult do
  @moduledoc """
  Struct representing a single parsed git grep match.

  Each result corresponds to one line of output from `git grep`,
  containing the file path, optional line number, and matched content.
  """

  @type t :: %__MODULE__{
          file: String.t(),
          line_number: non_neg_integer() | nil,
          content: String.t()
        }

  defstruct [:file, :line_number, :content]
end
