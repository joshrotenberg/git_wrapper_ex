defmodule Git.InterpretTrailersTest do
  use ExUnit.Case, async: true

  alias Git.Commands.InterpretTrailers
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
        "git_interpret_trailers_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir, env: @env)
    {:ok, :done} = Git.init(config: cfg)

    {:ok, :done} =
      Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)

    {:ok, :done} =
      Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {tmp_dir, cfg}
  end

  describe "args/1" do
    test "builds args with no options" do
      assert InterpretTrailers.args(%InterpretTrailers{}) == ["interpret-trailers"]
    end

    test "builds args with parse flag" do
      assert InterpretTrailers.args(%InterpretTrailers{parse: true}) ==
               ["interpret-trailers", "--only-trailers"]
    end

    test "builds args with single trailer" do
      assert InterpretTrailers.args(%InterpretTrailers{
               trailers: ["Signed-off-by: Test User <test@test.com>"]
             }) ==
               [
                 "interpret-trailers",
                 "--trailer",
                 "Signed-off-by: Test User <test@test.com>"
               ]
    end

    test "builds args with multiple trailers" do
      assert InterpretTrailers.args(%InterpretTrailers{
               trailers: ["Signed-off-by: A", "Reviewed-by: B"]
             }) ==
               [
                 "interpret-trailers",
                 "--trailer",
                 "Signed-off-by: A",
                 "--trailer",
                 "Reviewed-by: B"
               ]
    end

    test "builds args with in_place and file" do
      assert InterpretTrailers.args(%InterpretTrailers{in_place: true, file: "msg.txt"}) ==
               ["interpret-trailers", "--in-place", "msg.txt"]
    end

    test "builds args with trim_empty" do
      assert InterpretTrailers.args(%InterpretTrailers{trim_empty: true}) ==
               ["interpret-trailers", "--trim-empty"]
    end

    test "builds args with where option" do
      assert InterpretTrailers.args(%InterpretTrailers{where: "end"}) ==
               ["interpret-trailers", "--where", "end"]
    end

    test "builds args with if_exists option" do
      assert InterpretTrailers.args(%InterpretTrailers{if_exists: "replace"}) ==
               ["interpret-trailers", "--if-exists", "replace"]
    end

    test "builds args with if_missing option" do
      assert InterpretTrailers.args(%InterpretTrailers{if_missing: "doNothing"}) ==
               ["interpret-trailers", "--if-missing", "doNothing"]
    end

    test "builds args with unfold flag" do
      assert InterpretTrailers.args(%InterpretTrailers{unfold: true}) ==
               ["interpret-trailers", "--unfold"]
    end

    test "builds args with no_divider flag" do
      assert InterpretTrailers.args(%InterpretTrailers{no_divider: true}) ==
               ["interpret-trailers", "--no-divider"]
    end

    test "builds args with file" do
      assert InterpretTrailers.args(%InterpretTrailers{file: "commit_msg.txt"}) ==
               ["interpret-trailers", "commit_msg.txt"]
    end
  end

  describe "git interpret-trailers" do
    test "adds a trailer to a message file" do
      {tmp_dir, cfg} = setup_repo()

      msg_file = Path.join(tmp_dir, "commit_msg.txt")
      File.write!(msg_file, "Initial commit\n")

      {:ok, output} =
        Git.interpret_trailers(
          trailers: ["Signed-off-by: Test User <test@test.com>"],
          file: msg_file,
          config: cfg
        )

      assert output =~ "Initial commit"
      assert output =~ "Signed-off-by: Test User <test@test.com>"
    end

    test "parses trailers from a message file" do
      {tmp_dir, cfg} = setup_repo()

      msg_file = Path.join(tmp_dir, "commit_msg.txt")

      File.write!(
        msg_file,
        "Subject line\n\nBody text\n\nSigned-off-by: Test User <test@test.com>\n"
      )

      {:ok, output} =
        Git.interpret_trailers(
          parse: true,
          file: msg_file,
          config: cfg
        )

      assert output =~ "Signed-off-by: Test User <test@test.com>"
      refute output =~ "Subject line"
    end

    test "adds multiple trailers" do
      {tmp_dir, cfg} = setup_repo()

      msg_file = Path.join(tmp_dir, "commit_msg.txt")
      File.write!(msg_file, "feat: new feature\n")

      {:ok, output} =
        Git.interpret_trailers(
          trailers: [
            "Signed-off-by: Alice <alice@test.com>",
            "Reviewed-by: Bob <bob@test.com>"
          ],
          file: msg_file,
          config: cfg
        )

      assert output =~ "Signed-off-by: Alice <alice@test.com>"
      assert output =~ "Reviewed-by: Bob <bob@test.com>"
    end

    test "edits file in place" do
      {tmp_dir, cfg} = setup_repo()

      msg_file = Path.join(tmp_dir, "commit_msg.txt")
      File.write!(msg_file, "fix: bug fix\n")

      {:ok, _output} =
        Git.interpret_trailers(
          trailers: ["Signed-off-by: Test User <test@test.com>"],
          in_place: true,
          file: msg_file,
          config: cfg
        )

      updated = File.read!(msg_file)
      assert updated =~ "Signed-off-by: Test User <test@test.com>"
    end
  end
end
