defmodule Git.LsRemoteEntry do
  @moduledoc """
  Struct representing a single entry from `git ls-remote` output.

  Each entry contains the object SHA and the ref name. Symref lines
  (from `--symref`) are included with `sha` set to `nil`.
  """

  @type t :: %__MODULE__{
          sha: String.t() | nil,
          ref: String.t()
        }

  defstruct [
    :sha,
    :ref
  ]
end
