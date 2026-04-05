defmodule Git.RevertResult do
  @moduledoc """
  Represents the parsed result of a `git revert` command.

  Returned by a successful revert operation. For `--abort`, `--continue`,
  and `--skip` operations, `{:ok, :done}` is returned instead.
  """

  @type t :: %__MODULE__{
          conflicts: boolean(),
          raw: String.t()
        }

  defstruct conflicts: false,
            raw: ""

  @doc """
  Parses the output of `git revert` into a `Git.RevertResult` struct.

  Checks for `"CONFLICT"` in the output to determine if there were merge
  conflicts during the revert.

  ## Examples

      iex> Git.RevertResult.parse("Reverting abc1234\\n[main def5678] Revert \\"some commit\\"\\n")
      %Git.RevertResult{conflicts: false, raw: "Reverting abc1234\\n[main def5678] Revert \\"some commit\\"\\n"}

      iex> Git.RevertResult.parse("CONFLICT (content): Merge conflict in file.txt\\n")
      %Git.RevertResult{conflicts: true, raw: "CONFLICT (content): Merge conflict in file.txt\\n"}

  """
  @spec parse(String.t()) :: t()
  def parse(output) do
    %__MODULE__{
      conflicts: String.contains?(output, "CONFLICT"),
      raw: output
    }
  end
end
