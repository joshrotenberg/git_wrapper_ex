defmodule Git.Checkout do
  @moduledoc """
  Represents the result of a `git checkout` branch operation.

  Returned by `Git.checkout/1` when switching to or creating a branch.
  For file restore operations, `{:ok, :done}` is returned instead.
  """

  @type t :: %__MODULE__{
          branch: String.t() | nil,
          created: boolean()
        }

  defstruct [:branch, created: false]

  @doc """
  Parses the output of `git checkout` for branch operations.

  Handles the following output patterns:

    - `"Switched to a new branch 'name'"` — created and switched
    - `"Switched to branch 'name'"` — switched to existing branch
    - `"Already on 'name'"` — already on the requested branch

  ## Examples

      iex> Git.Checkout.parse("Switched to a new branch 'feat/new'\\n")
      %Git.Checkout{branch: "feat/new", created: true}

      iex> Git.Checkout.parse("Switched to branch 'main'\\n")
      %Git.Checkout{branch: "main", created: false}

      iex> Git.Checkout.parse("Already on 'main'\\n")
      %Git.Checkout{branch: "main", created: false}

  """
  @spec parse(String.t()) :: t()
  def parse(output) do
    cond do
      String.contains?(output, "Switched to a new branch") ->
        %__MODULE__{branch: extract_branch(output), created: true}

      String.contains?(output, "Switched to branch") ->
        %__MODULE__{branch: extract_branch(output), created: false}

      String.contains?(output, "Switched to and reset branch") ->
        %__MODULE__{branch: extract_branch(output), created: false}

      String.contains?(output, "Already on") ->
        %__MODULE__{branch: extract_branch(output), created: false}

      true ->
        %__MODULE__{}
    end
  end

  @spec extract_branch(String.t()) :: String.t() | nil
  defp extract_branch(output) do
    case Regex.run(~r/'([^']+)'/, output) do
      [_, branch] -> branch
      _ -> nil
    end
  end
end
