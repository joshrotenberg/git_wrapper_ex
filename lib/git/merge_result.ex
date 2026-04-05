defmodule Git.MergeResult do
  @moduledoc """
  Represents the parsed result of a `git merge` command.

  Returned by `Git.merge/2` on a successful merge. For `--abort`
  operations, `{:ok, :done}` is returned instead.
  """

  @type t :: %__MODULE__{
          fast_forward: boolean(),
          already_up_to_date: boolean()
        }

  defstruct fast_forward: false,
            already_up_to_date: false

  @doc """
  Parses the output of `git merge` into a `Git.MergeResult` struct.

  Handles the following output patterns:

    - `"Fast-forward"` — the merge was a fast-forward
    - `"Already up to date."` — nothing to merge
    - `"Merge made by the ..."` — a merge commit was created

  ## Examples

      iex> Git.MergeResult.parse("Updating abc1234..def5678\\nFast-forward\\n 1 file changed, 1 insertion(+)\\n")
      %Git.MergeResult{fast_forward: true, already_up_to_date: false}

      iex> Git.MergeResult.parse("Already up to date.\\n")
      %Git.MergeResult{fast_forward: false, already_up_to_date: true}

      iex> Git.MergeResult.parse("Merge made by the 'ort' strategy.\\n 1 file changed, 1 insertion(+)\\n")
      %Git.MergeResult{fast_forward: false, already_up_to_date: false}

  """
  @spec parse(String.t()) :: t()
  def parse(output) do
    %__MODULE__{
      fast_forward: String.contains?(output, "Fast-forward"),
      already_up_to_date: String.contains?(output, "Already up to date.")
    }
  end
end
