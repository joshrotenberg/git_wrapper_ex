defmodule Git.RebaseResult do
  @moduledoc """
  Represents the parsed result of a `git rebase` command.

  Returned by the rebase command on a successful (exit code 0) rebase operation.
  For abort, continue, and skip operations, `{:ok, :done}` is returned instead.
  """

  @type t :: %__MODULE__{
          up_to_date: boolean(),
          fast_forward: boolean(),
          conflicts: boolean(),
          raw: String.t()
        }

  defstruct up_to_date: false,
            fast_forward: false,
            conflicts: false,
            raw: ""

  @doc """
  Parses the output of `git rebase` into a `Git.RebaseResult` struct.

  Checks for known output patterns:

    - `"is up to date"` -- nothing to rebase
    - `"Fast-forwarded"` -- the rebase was a fast-forward
    - `"CONFLICT"` -- merge conflicts were encountered

  ## Examples

      iex> Git.RebaseResult.parse("Current branch main is up to date.\\n")
      %Git.RebaseResult{up_to_date: true, fast_forward: false, conflicts: false, raw: "Current branch main is up to date.\\n"}

      iex> Git.RebaseResult.parse("Successfully rebased and updated refs/heads/feat.\\n")
      %Git.RebaseResult{up_to_date: false, fast_forward: false, conflicts: false, raw: "Successfully rebased and updated refs/heads/feat.\\n"}

  """
  @spec parse(String.t()) :: t()
  def parse(output) do
    %__MODULE__{
      up_to_date: String.contains?(output, "is up to date"),
      fast_forward: String.contains?(output, "Fast-forwarded"),
      conflicts: String.contains?(output, "CONFLICT"),
      raw: output
    }
  end
end
