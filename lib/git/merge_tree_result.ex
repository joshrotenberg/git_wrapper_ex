defmodule Git.MergeTreeResult do
  @moduledoc """
  Result of `Git.merge_tree/3` (`git merge-tree --write-tree`).

  Represents a three-way merge performed entirely in the object database, with
  no working tree or index involvement:

    * `:tree` - SHA of the resulting merged tree (written to the object database
      regardless of conflicts)
    * `:clean` - `true` when the merge had no conflicts, `false` otherwise
    * `:conflicts` - the paths that conflicted (empty when `:clean` is `true`)
  """

  @type t :: %__MODULE__{
          tree: String.t(),
          clean: boolean(),
          conflicts: [String.t()]
        }

  defstruct [:tree, clean: true, conflicts: []]
end
