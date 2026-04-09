defmodule GitUIWeb.LogLive do
  use GitUIWeb, :live_view

  alias GitUI.GitRepo

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Commit Log", filter: "", page: 1) |> load_commits()}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply, assign(socket, filter: filter, page: 1) |> load_commits()}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    {:noreply, assign(socket, page: socket.assigns.page + 1) |> load_commits()}
  end

  defp load_commits(socket) do
    config = GitRepo.config()

    log_opts = [
      config: config,
      max_count: @per_page * socket.assigns.page
    ]

    log_opts =
      case socket.assigns.filter do
        "" -> log_opts
        filter -> Keyword.put(log_opts, :grep, filter)
      end

    commits =
      case Git.log(log_opts) do
        {:ok, commits} -> commits
        _ -> []
      end

    assign(socket, commits: commits)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Commit Log</h1>
        <.link navigate={~p"/"} class="text-sm text-blue-600 hover:underline">
          Back to dashboard
        </.link>
      </div>

      <form phx-change="filter" class="flex gap-2">
        <input
          type="text"
          name="filter"
          value={@filter}
          placeholder="Filter commits..."
          class="flex-1 rounded-md border-zinc-300 shadow-sm text-sm"
          phx-debounce="300"
        />
      </form>

      <div class="bg-white rounded-lg shadow overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-zinc-50 text-left">
            <tr>
              <th class="px-4 py-2 font-medium text-zinc-500">Hash</th>
              <th class="px-4 py-2 font-medium text-zinc-500">Message</th>
              <th class="px-4 py-2 font-medium text-zinc-500">Author</th>
              <th class="px-4 py-2 font-medium text-zinc-500">Date</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={commit <- @commits} class="border-t border-zinc-100 hover:bg-zinc-50">
              <td class="px-4 py-2 font-mono text-blue-600">{commit.abbreviated_hash}</td>
              <td class="px-4 py-2 truncate max-w-md">{commit.subject}</td>
              <td class="px-4 py-2 text-zinc-600">{commit.author_name}</td>
              <td class="px-4 py-2 text-zinc-400 whitespace-nowrap">
                {commit.date}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="text-center">
        <button
          phx-click="load-more"
          class="px-4 py-2 text-sm bg-zinc-100 hover:bg-zinc-200 rounded-md"
        >
          Load more
        </button>
      </div>
    </div>
    """
  end
end
