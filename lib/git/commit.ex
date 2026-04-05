defmodule Git.Commit do
  @moduledoc """
  Struct representing a single parsed git commit entry.
  """

  @type t :: %__MODULE__{
          hash: String.t(),
          abbreviated_hash: String.t(),
          author_name: String.t(),
          author_email: String.t(),
          date: String.t(),
          subject: String.t(),
          body: String.t()
        }

  defstruct [
    :hash,
    :abbreviated_hash,
    :author_name,
    :author_email,
    :date,
    :subject,
    body: ""
  ]
end
