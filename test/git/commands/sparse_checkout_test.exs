defmodule Git.SparseCheckoutTest do
  use ExUnit.Case, async: true

  alias Git.Commands.SparseCheckout
  alias Git.Config

  @env [
    {"GIT_AUTHOR_NAME", "Test User"},
    {"GIT_AUTHOR_EMAIL", "test@test.com"},
    {"GIT_COMMITTER_NAME", "Test User"},
    {"GIT_COMMITTER_EMAIL", "test@test.com"}
  ]

  defp setup_repo do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_sparse_checkout_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir, env: @env)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)
    {:ok, _} = Git.commit("initial", allow_empty: true, config: cfg)
    {tmp_dir, cfg}
  end

  setup do
    {tmp_dir, config} = setup_repo()
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir, config: config}
  end

  describe "Git.Commands.SparseCheckout args/1" do
    test "builds args for list (default)" do
      assert SparseCheckout.args(%SparseCheckout{}) == ["sparse-checkout", "list"]
    end

    test "builds args for init" do
      assert SparseCheckout.args(%SparseCheckout{init: true}) == ["sparse-checkout", "init"]
    end

    test "builds args for init with cone mode" do
      assert SparseCheckout.args(%SparseCheckout{init: true, cone: true}) ==
               ["sparse-checkout", "init", "--cone"]
    end

    test "builds args for init with sparse_index" do
      assert SparseCheckout.args(%SparseCheckout{init: true, sparse_index: true}) ==
               ["sparse-checkout", "init", "--sparse-index"]
    end

    test "builds args for init with no_sparse_index" do
      assert SparseCheckout.args(%SparseCheckout{init: true, no_sparse_index: true}) ==
               ["sparse-checkout", "init", "--no-sparse-index"]
    end

    test "builds args for set with patterns" do
      assert SparseCheckout.args(%SparseCheckout{set: ["src/", "docs/"]}) ==
               ["sparse-checkout", "set", "src/", "docs/"]
    end

    test "builds args for set with cone mode" do
      assert SparseCheckout.args(%SparseCheckout{set: ["src/"], cone: true}) ==
               ["sparse-checkout", "set", "--cone", "src/"]
    end

    test "builds args for set with no_cone mode" do
      assert SparseCheckout.args(%SparseCheckout{set: ["*.ex"], no_cone: true}) ==
               ["sparse-checkout", "set", "--no-cone", "*.ex"]
    end

    test "builds args for add with patterns" do
      assert SparseCheckout.args(%SparseCheckout{add: ["tests/"]}) ==
               ["sparse-checkout", "add", "tests/"]
    end

    test "builds args for add with cone mode" do
      assert SparseCheckout.args(%SparseCheckout{add: ["tests/"], cone: true}) ==
               ["sparse-checkout", "add", "--cone", "tests/"]
    end

    test "builds args for disable" do
      assert SparseCheckout.args(%SparseCheckout{disable: true}) ==
               ["sparse-checkout", "disable"]
    end

    test "builds args for reapply" do
      assert SparseCheckout.args(%SparseCheckout{reapply: true}) ==
               ["sparse-checkout", "reapply"]
    end

    test "builds args for check_rules" do
      assert SparseCheckout.args(%SparseCheckout{check_rules: true}) ==
               ["sparse-checkout", "check-rules"]
    end
  end

  describe "git sparse-checkout integration" do
    test "init, set, list, and disable workflow", %{tmp_dir: tmp_dir, config: config} do
      # Create files in different directories
      src_dir = Path.join(tmp_dir, "src")
      docs_dir = Path.join(tmp_dir, "docs")
      tests_dir = Path.join(tmp_dir, "tests")
      File.mkdir_p!(src_dir)
      File.mkdir_p!(docs_dir)
      File.mkdir_p!(tests_dir)
      File.write!(Path.join(src_dir, "main.ex"), "defmodule Main do\nend\n")
      File.write!(Path.join(docs_dir, "guide.md"), "# Guide\n")
      File.write!(Path.join(tests_dir, "main_test.ex"), "defmodule MainTest do\nend\n")
      {:ok, :done} = Git.add(all: true, config: config)
      {:ok, _} = Git.commit("add project files", config: config)

      # Init sparse-checkout with cone mode
      assert {:ok, :done} = Git.sparse_checkout(init: true, cone: true, config: config)

      # Set patterns to only include src directory
      assert {:ok, :done} = Git.sparse_checkout(set: ["src"], cone: true, config: config)

      # List patterns
      assert {:ok, patterns} = Git.sparse_checkout(config: config)
      assert is_list(patterns)
      assert "src" in patterns

      # Disable sparse-checkout
      assert {:ok, :done} = Git.sparse_checkout(disable: true, config: config)
    end
  end
end
