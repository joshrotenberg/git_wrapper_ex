defmodule GitWrapper.DiffFile do
  @moduledoc """
  Parsed representation of a single file's contribution to a `git diff --stat`.

  Contains the file path, insertion and deletion counts, and a flag for
  binary files (which do not have line-level stats).
  """

  @type t :: %__MODULE__{
          path: String.t(),
          insertions: non_neg_integer(),
          deletions: non_neg_integer(),
          binary: boolean()
        }

  defstruct [:path, insertions: 0, deletions: 0, binary: false]
end
