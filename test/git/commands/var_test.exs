defmodule Git.Commands.VarTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Var
  alias Git.Config

  describe "args/1" do
    test "list mode when no name is given" do
      assert Var.args(%Var{}) == ["var", "-l"]
    end

    test "single-variable mode" do
      assert Var.args(%Var{name: "GIT_EDITOR"}) == ["var", "GIT_EDITOR"]
    end
  end

  describe "parse_output/2" do
    test "list mode parses NAME=value lines into a map" do
      # args/1 sets the list mode.
      Var.args(%Var{})
      output = "user.name=Test User\nuser.email=test@test.com\ninit.defaultbranch=main\n"

      assert Var.parse_output(output, 0) ==
               {:ok,
                %{
                  "user.name" => "Test User",
                  "user.email" => "test@test.com",
                  "init.defaultbranch" => "main"
                }}
    end

    test "list mode keeps values that contain equals signs" do
      Var.args(%Var{})

      assert Var.parse_output("filter.lfs.clean=git-lfs clean -- %f\n", 0) ==
               {:ok, %{"filter.lfs.clean" => "git-lfs clean -- %f"}}
    end

    test "single mode returns the trimmed value" do
      Var.args(%Var{name: "GIT_EDITOR"})
      assert Var.parse_output("vim\n", 0) == {:ok, "vim"}
    end

    test "non-zero exit returns error" do
      Var.args(%Var{name: "GIT_NOPE"})
      assert Var.parse_output("usage: git var", 129) == {:error, {"usage: git var", 129}}
    end
  end

  describe "Git.var/1 integration" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "git_var_test_#{:erlang.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      cfg = Config.new(working_dir: tmp)
      {:ok, :done} = Git.init(config: cfg)
      {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)

      {:ok, :done} =
        Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)

      on_exit(fn -> Git.TestHelpers.rm_rf(tmp) end)
      %{config: cfg}
    end

    test "lists variables as a map", %{config: config} do
      {:ok, vars} = Git.var(config: config)
      assert is_map(vars)
      assert vars["user.email"] == "test@test.com"
    end

    test "looks up a single variable", %{config: config} do
      {:ok, ident} = Git.var(name: "GIT_COMMITTER_IDENT", config: config)
      assert is_binary(ident)
      assert String.contains?(ident, "test@test.com")
    end

    test "returns an error for an unknown variable", %{config: config} do
      assert {:error, _} = Git.var(name: "GIT_DEFINITELY_NOT_A_VAR", config: config)
    end
  end
end
