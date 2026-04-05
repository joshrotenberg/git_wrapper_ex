defmodule Git.ReflogEntry do
  @moduledoc """
  Parsed representation of a single git reflog entry.

  Contains the full and abbreviated commit hashes, the reflog selector
  (e.g. `HEAD@{0}`), the action that produced the entry, and the
  associated message.
  """

  @type t :: %__MODULE__{
          hash: String.t(),
          abbreviated_hash: String.t(),
          selector: String.t(),
          action: String.t(),
          message: String.t()
        }

  defstruct [:hash, :abbreviated_hash, :selector, :action, :message]
end
