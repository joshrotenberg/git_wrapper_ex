defmodule Git.BisectResult do
  @moduledoc """
  Result of a git bisect operation.

  The `status` field indicates the current state of the bisect session:

    * `:started` - a new bisect session was started
    * `:stepping` - bisect is narrowing down the bad commit
    * `:found` - the first bad commit has been identified
    * `:done` - the bisect session was reset/ended
  """

  @type status :: :started | :stepping | :found | :done

  @type t :: %__MODULE__{
          status: status(),
          current_commit: String.t() | nil,
          bad_commit: String.t() | nil,
          raw: String.t()
        }

  defstruct [:status, :current_commit, :bad_commit, :raw]
end
