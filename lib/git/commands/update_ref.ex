defmodule Git.Commands.UpdateRef do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git update-ref`.

  Updates the object name stored in a ref safely. Supports conditional
  updates (compare-and-swap), reflog messages, and deletion.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          ref: String.t() | nil,
          new_value: String.t() | nil,
          old_value: String.t() | nil,
          delete: boolean(),
          create_reflog: boolean(),
          message: String.t() | nil,
          no_deref: boolean()
        }

  defstruct ref: nil,
            new_value: nil,
            old_value: nil,
            delete: false,
            create_reflog: false,
            message: nil,
            no_deref: false

  @doc """
  Returns the argument list for `git update-ref`.

  ## Examples

      iex> Git.Commands.UpdateRef.args(%Git.Commands.UpdateRef{ref: "refs/heads/main", new_value: "abc123"})
      ["update-ref", "refs/heads/main", "abc123"]

      iex> Git.Commands.UpdateRef.args(%Git.Commands.UpdateRef{ref: "refs/heads/main", new_value: "abc123", old_value: "def456"})
      ["update-ref", "refs/heads/main", "abc123", "def456"]

      iex> Git.Commands.UpdateRef.args(%Git.Commands.UpdateRef{ref: "refs/heads/main", new_value: "abc123", message: "reset"})
      ["update-ref", "-m", "reset", "refs/heads/main", "abc123"]

      iex> Git.Commands.UpdateRef.args(%Git.Commands.UpdateRef{ref: "refs/heads/old", delete: true})
      ["update-ref", "-d", "refs/heads/old"]

      iex> Git.Commands.UpdateRef.args(%Git.Commands.UpdateRef{ref: "HEAD", new_value: "abc123", no_deref: true})
      ["update-ref", "--no-deref", "HEAD", "abc123"]

      iex> Git.Commands.UpdateRef.args(%Git.Commands.UpdateRef{ref: "refs/heads/main", new_value: "abc123", create_reflog: true})
      ["update-ref", "--create-reflog", "refs/heads/main", "abc123"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["update-ref"]
    |> maybe_add_flag(command.no_deref, "--no-deref")
    |> maybe_add_flag(command.create_reflog, "--create-reflog")
    |> maybe_add_message(command.message)
    |> maybe_add_delete_or_update(command)
  end

  @doc """
  Parses the output of `git update-ref`.

  Always returns `{:ok, :done}` on success (exit code 0) since
  `git update-ref` produces no meaningful output.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(_stdout, 0), do: {:ok, :done}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_message(args, nil), do: args
  defp maybe_add_message(args, message), do: args ++ ["-m", message]

  defp maybe_add_delete_or_update(args, %{delete: true, ref: ref}) do
    args ++ ["-d", ref]
  end

  defp maybe_add_delete_or_update(args, %{ref: ref, new_value: new_value, old_value: old_value})
       when not is_nil(old_value) do
    args ++ [ref, new_value, old_value]
  end

  defp maybe_add_delete_or_update(args, %{ref: ref, new_value: new_value})
       when not is_nil(new_value) do
    args ++ [ref, new_value]
  end

  defp maybe_add_delete_or_update(args, %{ref: ref}) when not is_nil(ref) do
    args ++ [ref]
  end

  defp maybe_add_delete_or_update(args, _command), do: args
end
