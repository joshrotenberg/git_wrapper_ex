defmodule Git.ShowResult do
  @moduledoc """
  Represents the parsed result of a `git show` command.

  When the default format is used (no custom `--format` or `--oneline`), the
  commit header is parsed into a `Git.Commit` struct and the remaining
  output is captured as diff and stat text. When a custom format is provided,
  only the `raw` field is populated.
  """

  alias Git.Commit

  @type t :: %__MODULE__{
          commit: Commit.t() | nil,
          diff: String.t(),
          stat: String.t() | nil,
          raw: String.t()
        }

  defstruct commit: nil,
            diff: "",
            stat: nil,
            raw: ""
end
