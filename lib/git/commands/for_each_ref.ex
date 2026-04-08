defmodule Git.Commands.ForEachRef do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git for-each-ref`.

  Iterates over all refs matching the given pattern(s) and formats them
  according to the given format string. Useful for scripting and
  inspecting refs programmatically.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          format: String.t() | nil,
          sort: String.t() | [String.t()] | nil,
          count: non_neg_integer() | nil,
          pattern: String.t() | [String.t()] | nil,
          contains: String.t() | nil,
          merged: String.t() | nil,
          no_merged: String.t() | nil,
          points_at: String.t() | nil
        }

  defstruct format: nil,
            sort: nil,
            count: nil,
            pattern: nil,
            contains: nil,
            merged: nil,
            no_merged: nil,
            points_at: nil

  @doc """
  Returns the argument list for `git for-each-ref`.

  ## Examples

      iex> Git.Commands.ForEachRef.args(%Git.Commands.ForEachRef{})
      ["for-each-ref"]

      iex> Git.Commands.ForEachRef.args(%Git.Commands.ForEachRef{format: "%(refname)"})
      ["for-each-ref", "--format=%(refname)"]

      iex> Git.Commands.ForEachRef.args(%Git.Commands.ForEachRef{sort: "-creatordate", count: 5})
      ["for-each-ref", "--count=5", "--sort=-creatordate"]

      iex> Git.Commands.ForEachRef.args(%Git.Commands.ForEachRef{sort: ["-creatordate", "refname"]})
      ["for-each-ref", "--sort=-creatordate", "--sort=refname"]

      iex> Git.Commands.ForEachRef.args(%Git.Commands.ForEachRef{pattern: "refs/heads/"})
      ["for-each-ref", "refs/heads/"]

      iex> Git.Commands.ForEachRef.args(%Git.Commands.ForEachRef{pattern: ["refs/heads/", "refs/tags/"]})
      ["for-each-ref", "refs/heads/", "refs/tags/"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["for-each-ref"]
    |> maybe_add_value("--format=", command.format)
    |> maybe_add_value("--count=", command.count)
    |> maybe_add_list_or_value("--sort=", command.sort)
    |> maybe_add_value("--contains=", command.contains)
    |> maybe_add_value("--merged=", command.merged)
    |> maybe_add_value("--no-merged=", command.no_merged)
    |> maybe_add_value("--points-at=", command.points_at)
    |> maybe_add_patterns(command.pattern)
  end

  @doc """
  Parses the output of `git for-each-ref`.

  On success (exit code 0), returns `{:ok, output}` where output is the
  trimmed string. On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0), do: {:ok, String.trim(stdout)}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add_value(args, _prefix, nil), do: args
  defp maybe_add_value(args, prefix, value), do: args ++ ["#{prefix}#{value}"]

  defp maybe_add_list_or_value(args, _prefix, nil), do: args

  defp maybe_add_list_or_value(args, prefix, values) when is_list(values) do
    args ++ Enum.map(values, &"#{prefix}#{&1}")
  end

  defp maybe_add_list_or_value(args, prefix, value), do: args ++ ["#{prefix}#{value}"]

  defp maybe_add_patterns(args, nil), do: args
  defp maybe_add_patterns(args, patterns) when is_list(patterns), do: args ++ patterns
  defp maybe_add_patterns(args, pattern), do: args ++ [pattern]
end
