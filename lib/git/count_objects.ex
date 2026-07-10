defmodule Git.CountObjects do
  @moduledoc """
  Parsed representation of `git count-objects -v` output.

  Reports the number and on-disk size of loose and packed objects. Sizes are
  reported by git in KiB. Fields default to `0` when git omits the
  corresponding line.
  """

  @type t :: %__MODULE__{
          count: non_neg_integer(),
          size: non_neg_integer(),
          in_pack: non_neg_integer(),
          packs: non_neg_integer(),
          size_pack: non_neg_integer(),
          prune_packable: non_neg_integer(),
          garbage: non_neg_integer(),
          size_garbage: non_neg_integer()
        }

  defstruct count: 0,
            size: 0,
            in_pack: 0,
            packs: 0,
            size_pack: 0,
            prune_packable: 0,
            garbage: 0,
            size_garbage: 0

  @keys %{
    "count" => :count,
    "size" => :size,
    "in-pack" => :in_pack,
    "packs" => :packs,
    "size-pack" => :size_pack,
    "prune-packable" => :prune_packable,
    "garbage" => :garbage,
    "size-garbage" => :size_garbage
  }

  @doc """
  Parses the verbose output of `git count-objects -v` into a struct.

  Each line has the form `key: value`. Unknown keys are ignored.

  ## Examples

      iex> Git.CountObjects.parse("count: 3\\nsize: 12\\nin-pack: 0\\npacks: 0\\nsize-pack: 0\\nprune-packable: 0\\ngarbage: 0\\nsize-garbage: 0\\n")
      %Git.CountObjects{count: 3, size: 12}

  """
  @spec parse(String.t()) :: t()
  def parse(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reduce(%__MODULE__{}, &apply_line/2)
  end

  defp apply_line(line, acc) do
    with [key, value] <- String.split(line, ":", parts: 2),
         field when not is_nil(field) <- Map.get(@keys, String.trim(key)) do
      struct(acc, [{field, parse_int(value)}])
    else
      _ -> acc
    end
  end

  defp parse_int(value) do
    case Integer.parse(String.trim(value)) do
      {n, _rest} -> n
      :error -> 0
    end
  end
end
