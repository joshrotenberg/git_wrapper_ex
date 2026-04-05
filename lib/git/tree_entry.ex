defmodule Git.TreeEntry do
  @moduledoc """
  Struct representing a single entry from `git ls-tree` output.

  Each entry contains the file mode, object type, SHA, path, and
  optionally the object size (when `--long` is used).
  """

  @type t :: %__MODULE__{
          mode: String.t(),
          type: :blob | :tree | :commit,
          sha: String.t(),
          path: String.t(),
          size: non_neg_integer() | nil
        }

  defstruct [
    :mode,
    :type,
    :sha,
    :path,
    :size
  ]
end
