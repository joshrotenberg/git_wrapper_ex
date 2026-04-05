defmodule Git.PullResult do
  @moduledoc """
  Represents the parsed result of a `git pull` command.

  Contains boolean flags indicating the type of pull that occurred and the
  raw output string for further inspection.
  """

  @type t :: %__MODULE__{
          already_up_to_date: boolean(),
          fast_forward: boolean(),
          merge_commit: boolean(),
          conflicts: boolean(),
          raw: String.t()
        }

  defstruct already_up_to_date: false,
            fast_forward: false,
            merge_commit: false,
            conflicts: false,
            raw: ""

  @doc """
  Parses the output of `git pull` into a `Git.PullResult` struct.

  Checks the output for known patterns:

  - `"Already up to date"` -- no changes pulled
  - `"Fast-forward"` -- fast-forward merge
  - `"Merge made by"` -- a merge commit was created
  - `"CONFLICT"` -- merge conflicts detected

  ## Examples

      iex> Git.PullResult.parse("Already up to date.\\n")
      %Git.PullResult{already_up_to_date: true, fast_forward: false, merge_commit: false, conflicts: false, raw: "Already up to date.\\n"}

      iex> result = Git.PullResult.parse("Updating abc..def\\nFast-forward\\n file.txt | 1 +\\n")
      iex> result.fast_forward
      true

  """
  @spec parse(String.t()) :: t()
  def parse(output) do
    %__MODULE__{
      already_up_to_date: String.contains?(output, "Already up to date"),
      fast_forward: String.contains?(output, "Fast-forward"),
      merge_commit: String.contains?(output, "Merge made by"),
      conflicts: String.contains?(output, "CONFLICT"),
      raw: output
    }
  end
end
