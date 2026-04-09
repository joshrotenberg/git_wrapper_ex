defmodule GitUIWeb.BranchesLive do
  use GitUIWeb, :live_view

  alias GitUI.GitRepo

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Branches") |> load_data()}
  end

  defp load_data(socket) do
    config = GitRepo.config()
    opts = [config: config]

    current =
      case Git.Branches.current(opts) do
        {:ok, name} -> name
        _ -> nil
      end

    branches =
      case Git.branch(opts) do
        {:ok, branches} -> branches
        _ -> []
      end

    recent =
      case Git.Branches.recent(Keyword.put(opts, :count, 20)) do
        {:ok, recent} -> recent
        _ -> []
      end

    assign(socket,
      current_branch: current,
      branches: branches,
      recent: recent
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Branches</h1>
        <.link navigate={~p"/"} class="text-sm text-blue-600 hover:underline">
          Back to dashboard
        </.link>
      </div>

      <div class="bg-white rounded-lg shadow p-4">
        <h2 class="text-lg font-semibold mb-3">
          Current: <span class="font-mono text-blue-600">{@current_branch}</span>
        </h2>

        <h3 class="text-sm font-medium text-zinc-500 mb-2 mt-4">All Local Branches</h3>
        <div class="space-y-1">
          <div
            :for={branch <- @branches}
            class={"flex items-center gap-2 px-2 py-1 rounded text-sm #{if branch.current, do: "bg-blue-50", else: ""}"}
          >
            <span :if={branch.current} class="text-blue-600 font-bold">*</span>
            <span :if={!branch.current} class="w-3"></span>
            <span class={"font-mono #{if branch.current, do: "font-bold text-blue-600", else: ""}"}>{branch.name}</span>
          </div>
        </div>
      </div>

      <div class="bg-white rounded-lg shadow p-4">
        <h2 class="text-lg font-semibold mb-3">Recent Activity</h2>
        <div class="space-y-2">
          <div :for={branch <- @recent} class="flex gap-3 text-sm">
            <span class={"font-mono font-semibold #{if branch.name == @current_branch, do: "text-blue-600", else: ""}"}>{branch.name}</span>
            <span class="truncate text-zinc-500">{branch.subject}</span>
            <span class="text-zinc-400 shrink-0 ml-auto">{branch.date}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
