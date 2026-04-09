defmodule GitUIWeb.BlameLive do
  use GitUIWeb, :live_view

  alias GitUI.GitRepo

  @impl true
  def mount(%{"path" => path}, _session, socket) do
    # path comes in as a list of segments from the catch-all
    file_path = path |> List.wrap() |> Enum.join("/")

    {:ok, assign(socket, page_title: "Blame: #{file_path}", file_path: file_path) |> load_blame()}
  end

  defp load_blame(socket) do
    config = GitRepo.config()

    blame_entries =
      case Git.blame(socket.assigns.file_path, config: config) do
        {:ok, entries} -> entries
        _ -> []
      end

    assign(socket, entries: blame_entries)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">
          Blame: <span class="font-mono text-blue-600">{@file_path}</span>
        </h1>
        <.link navigate={~p"/"} class="text-sm text-blue-600 hover:underline">
          Back to dashboard
        </.link>
      </div>

      <div :if={@entries == []} class="bg-white rounded-lg shadow p-8 text-center text-zinc-400">
        No blame data available for this file.
      </div>

      <div :if={@entries != []} class="bg-white rounded-lg shadow overflow-x-auto">
        <table class="w-full text-xs font-mono">
          <tbody>
            <tr :for={entry <- @entries} class="border-t border-zinc-100 hover:bg-zinc-50">
              <td class="px-2 py-0.5 text-blue-600 whitespace-nowrap">
                {String.slice(entry.hash, 0, 7)}
              </td>
              <td class="px-2 py-0.5 text-zinc-400 whitespace-nowrap">{entry.author}</td>
              <td class="px-2 py-0.5 text-zinc-300 text-right select-none">{entry.line_number}</td>
              <td class="px-2 py-0.5 whitespace-pre">{entry.content}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
