defmodule Git.Commands.CheckAttr do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git check-attr`.

  Reports the gitattributes that apply to given paths. This is the
  attributes analogue of `Git.Commands.CheckIgnore`.

  Pass explicit attribute names in `:attrs`, or set `:all` to report every
  attribute that is set on each path. `:cached` reads `.gitattributes` from
  the index instead of the working tree.

  Output is always requested with `-z` (NUL-delimited records) so paths and
  values containing spaces or newlines parse unambiguously.

  Stdin mode (`--stdin`) is intentionally not supported because it requires
  stdin piping which cannot be driven programmatically via `System.cmd/3`.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          attrs: [String.t()],
          paths: [String.t()],
          all: boolean(),
          cached: boolean()
        }

  @type attribute :: %{path: String.t(), attr: String.t(), value: String.t()}

  defstruct attrs: [],
            paths: [],
            all: false,
            cached: false

  @doc """
  Returns the argument list for `git check-attr`.

  Attributes and paths are separated with `--` so paths are never mistaken
  for attribute names.

  ## Examples

      iex> Git.Commands.CheckAttr.args(%Git.Commands.CheckAttr{attrs: ["diff"], paths: ["foo.ex"]})
      ["check-attr", "-z", "diff", "--", "foo.ex"]

      iex> Git.Commands.CheckAttr.args(%Git.Commands.CheckAttr{attrs: ["diff", "text"], paths: ["foo.ex", "bar.png"]})
      ["check-attr", "-z", "diff", "text", "--", "foo.ex", "bar.png"]

      iex> Git.Commands.CheckAttr.args(%Git.Commands.CheckAttr{all: true, paths: ["foo.ex"]})
      ["check-attr", "-z", "-a", "--", "foo.ex"]

      iex> Git.Commands.CheckAttr.args(%Git.Commands.CheckAttr{attrs: ["diff"], paths: ["foo.ex"], cached: true})
      ["check-attr", "-z", "--cached", "diff", "--", "foo.ex"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["check-attr", "-z"]
    |> maybe_add_flag(command.cached, "--cached")
    |> add_attr_selection(command)
    |> add_paths(command.paths)
  end

  @doc """
  Parses the `-z` output of `git check-attr`.

  Returns `{:ok, [record]}` where each record is a map with `:path`, `:attr`,
  and `:value` keys. `:value` is the raw info string reported by git: one of
  `"set"`, `"unset"`, `"unspecified"`, or a custom attribute value.

  Empty output (for example `--all` on a path with no attributes) returns
  `{:ok, []}`. A non-zero exit code is a real error (unknown option, no
  attribute specified, and so on) and returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [attribute()]} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    records =
      stdout
      |> String.split(<<0>>, trim: true)
      |> Enum.chunk_every(3)
      |> Enum.flat_map(fn
        [path, attr, value] -> [%{path: path, attr: attr, value: value}]
        _ -> []
      end)

    {:ok, records}
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp add_attr_selection(args, %__MODULE__{all: true}), do: args ++ ["-a"]
  defp add_attr_selection(args, %__MODULE__{attrs: attrs}), do: args ++ attrs

  defp add_paths(args, []), do: args
  defp add_paths(args, paths), do: args ++ ["--" | paths]

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args
end
