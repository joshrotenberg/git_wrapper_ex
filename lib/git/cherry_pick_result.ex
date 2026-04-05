defmodule Git.CherryPickResult do
  @moduledoc """
  Represents the parsed result of a `git cherry-pick` command.

  Returned by the cherry-pick command on a successful (exit code 0) pick operation.
  For abort, continue, and skip operations, `{:ok, :done}` is returned instead.
  """

  @type t :: %__MODULE__{
          conflicts: boolean(),
          raw: String.t()
        }

  defstruct conflicts: false,
            raw: ""

  @doc """
  Parses the output of `git cherry-pick` into a `Git.CherryPickResult` struct.

  Checks for the `"CONFLICT"` pattern in the output to detect merge conflicts.

  ## Examples

      iex> Git.CherryPickResult.parse("[main abc1234] cherry-picked commit\\n 1 file changed, 1 insertion(+)\\n")
      %Git.CherryPickResult{conflicts: false, raw: "[main abc1234] cherry-picked commit\\n 1 file changed, 1 insertion(+)\\n"}

  """
  @spec parse(String.t()) :: t()
  def parse(output) do
    %__MODULE__{
      conflicts: String.contains?(output, "CONFLICT"),
      raw: output
    }
  end
end
