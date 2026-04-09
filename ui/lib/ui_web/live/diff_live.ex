defmodule GitUIWeb.DiffLive do
  use GitUIWeb, :live_view

  alias GitUI.GitRepo

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Diff", mode: "working", diff: nil) |> load_diff()}
  end

  @impl true
  def handle_event("switch-mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, mode: mode) |> load_diff()}
  end

  defp load_diff(socket) do
    config = GitRepo.config()

    diff_opts =
      case socket.assigns.mode do
        "staged" -> [config: config, staged: true]
        _ -> [config: config]
      end

    diff =
      case Git.diff(diff_opts) do
        {:ok, diff} -> diff
        _ -> nil
      end

    stat =
      case Git.diff(Keyword.put(diff_opts, :stat, true)) do
        {:ok, stat} -> stat
        _ -> nil
      end

    assign(socket, diff: diff, stat: stat)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Diff</h1>
        <.link navigate={~p"/"} class="text-sm text-blue-600 hover:underline">
          Back to dashboard
        </.link>
      </div>

      <div class="flex gap-2">
        <button
          phx-click="switch-mode"
          phx-value-mode="working"
          class={"px-3 py-1 rounded text-sm #{if @mode == "working", do: "bg-blue-600 text-white", else: "bg-zinc-100"}"}
        >
          Working Tree
        </button>
        <button
          phx-click="switch-mode"
          phx-value-mode="staged"
          class={"px-3 py-1 rounded text-sm #{if @mode == "staged", do: "bg-blue-600 text-white", else: "bg-zinc-100"}"}
        >
          Staged
        </button>
      </div>

      <div :if={@stat && length(@stat.files) > 0} class="bg-white rounded-lg shadow p-4">
        <h2 class="text-sm font-medium text-zinc-500 mb-2">File Stats</h2>
        <div class="space-y-1 text-sm font-mono">
          <div :for={file <- @stat.files} class="flex gap-2">
            <span class="text-green-600">+{file.insertions}</span>
            <span class="text-red-600">-{file.deletions}</span>
            <span>{file.path}</span>
          </div>
          <div class="border-t pt-1 mt-2 text-zinc-500">
            {length(@stat.files)} files, +{@stat.total_insertions} -{@stat.total_deletions}
          </div>
        </div>
      </div>

      <div :if={@diff && @diff.raw != ""} class="bg-zinc-900 rounded-lg shadow p-4 overflow-x-auto">
        <pre class="text-sm font-mono text-zinc-100 whitespace-pre">{colorize_diff(@diff.raw)}</pre>
      </div>

      <div
        :if={is_nil(@diff) || @diff.raw == ""}
        class="bg-white rounded-lg shadow p-8 text-center text-zinc-400"
      >
        No changes in {if @mode == "staged", do: "staging area", else: "working tree"}
      </div>
    </div>
    """
  end

  defp colorize_diff(raw) do
    raw
    |> String.split("\n")
    |> Enum.map(&colorize_line/1)
    |> Enum.intersperse("\n")
  end

  defp colorize_line("+" <> _ = line) do
    assigns = %{line: line}

    ~H"""
    <span class="text-green-400">{@line}</span>
    """
  end

  defp colorize_line("-" <> _ = line) do
    assigns = %{line: line}

    ~H"""
    <span class="text-red-400">{@line}</span>
    """
  end

  defp colorize_line("@@" <> _ = line) do
    assigns = %{line: line}

    ~H"""
    <span class="text-cyan-400">{@line}</span>
    """
  end

  defp colorize_line("diff " <> _ = line) do
    assigns = %{line: line}

    ~H"""
    <span class="text-yellow-400 font-bold">{@line}</span>
    """
  end

  defp colorize_line(line), do: line
end
