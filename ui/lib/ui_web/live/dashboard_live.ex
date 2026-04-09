defmodule GitUIWeb.DashboardLive do
  use GitUIWeb, :live_view

  alias GitUI.GitRepo

  @refresh_interval 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval)

    {:ok, assign(socket, page_title: "Dashboard") |> load_data()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load_data(socket)}
  end

  defp load_data(socket) do
    config = GitRepo.config()
    opts = [config: config]

    summary = load_summary(opts)
    recent_commits = load_recent_commits(opts)
    branches = load_branches(opts)
    status = load_status(opts)

    assign(socket,
      repo_path: GitRepo.repo_path(),
      summary: summary,
      recent_commits: recent_commits,
      branches: branches,
      status: status
    )
  end

  defp load_summary(opts) do
    case Git.Info.summary(opts) do
      {:ok, summary} -> summary
      _ -> %{}
    end
  end

  defp load_recent_commits(opts) do
    case Git.log(Keyword.put(opts, :max_count, 10)) do
      {:ok, commits} -> commits
      _ -> []
    end
  end

  defp load_branches(opts) do
    case Git.Branches.recent(Keyword.put(opts, :count, 10)) do
      {:ok, branches} -> branches
      _ -> []
    end
  end

  defp load_status(opts) do
    case Git.status(opts) do
      {:ok, status} -> status
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Repository Dashboard</h1>
        <span class="text-sm text-zinc-500 font-mono">{@repo_path}</span>
      </div>

      <%!-- Summary cards --%>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <.card title="Branch" value={@summary[:branch] || "unknown"} />
        <.card title="HEAD" value={short_hash(@summary[:commit])} />
        <.card
          title="Status"
          value={if @summary[:dirty], do: "dirty", else: "clean"}
          color={if @summary[:dirty], do: "yellow", else: "green"}
        />
        <.card
          title="Ahead/Behind"
          value={"#{@summary[:ahead] || 0} / #{@summary[:behind] || 0}"}
        />
      </div>

      <%!-- Working tree status --%>
      <div :if={@status && length(@status.entries) > 0} class="bg-white rounded-lg shadow p-4">
        <h2 class="text-lg font-semibold mb-3">Working Tree</h2>
        <div class="space-y-1 font-mono text-sm">
          <div :for={entry <- @status.entries} class="flex gap-2">
            <span class={"w-6 text-center font-bold #{status_color(entry)}"}>
              {status_indicator(entry)}
            </span>
            <span>{entry.path}</span>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <%!-- Recent commits --%>
        <div class="bg-white rounded-lg shadow p-4">
          <div class="flex items-center justify-between mb-3">
            <h2 class="text-lg font-semibold">Recent Commits</h2>
            <.link navigate={~p"/log"} class="text-sm text-blue-600 hover:underline">
              View all
            </.link>
          </div>
          <div class="space-y-2">
            <div :for={commit <- @recent_commits} class="flex gap-3 text-sm">
              <span class="font-mono text-blue-600 shrink-0">{commit.abbreviated_hash}</span>
              <span class="truncate">{commit.subject}</span>
              <span class="text-zinc-400 shrink-0 ml-auto">{commit.author_date_relative}</span>
            </div>
          </div>
        </div>

        <%!-- Recent branches --%>
        <div class="bg-white rounded-lg shadow p-4">
          <div class="flex items-center justify-between mb-3">
            <h2 class="text-lg font-semibold">Recent Branches</h2>
            <.link navigate={~p"/branches"} class="text-sm text-blue-600 hover:underline">
              View all
            </.link>
          </div>
          <div class="space-y-2">
            <div :for={branch <- @branches} class="flex gap-3 text-sm">
              <span class="font-mono font-semibold">{branch.name}</span>
              <span class="truncate text-zinc-500">{branch.subject}</span>
              <span class="text-zinc-400 shrink-0 ml-auto">{branch.date}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp short_hash(nil), do: "..."
  defp short_hash(hash) when byte_size(hash) > 7, do: String.slice(hash, 0, 7)
  defp short_hash(hash), do: hash

  defp status_indicator(%{index: "M"}), do: "M"
  defp status_indicator(%{index: "A"}), do: "A"
  defp status_indicator(%{index: "D"}), do: "D"
  defp status_indicator(%{index: "R"}), do: "R"
  defp status_indicator(%{working_tree: "M"}), do: "M"
  defp status_indicator(%{working_tree: "?"}), do: "?"
  defp status_indicator(%{working_tree: "D"}), do: "D"
  defp status_indicator(_), do: " "

  defp status_color(%{index: i}) when i in ["M", "A", "D", "R"], do: "text-green-600"
  defp status_color(%{working_tree: "?"}), do: "text-zinc-400"
  defp status_color(%{working_tree: w}) when w in ["M", "D"], do: "text-red-600"
  defp status_color(_), do: "text-zinc-500"

  attr :title, :string, required: true
  attr :value, :string, required: true
  attr :color, :string, default: nil

  defp card(assigns) do
    color_class =
      case assigns.color do
        "green" -> "text-green-600"
        "yellow" -> "text-yellow-600"
        "red" -> "text-red-600"
        _ -> "text-zinc-900"
      end

    assigns = assign(assigns, :color_class, color_class)

    ~H"""
    <div class="bg-white rounded-lg shadow p-4">
      <dt class="text-sm text-zinc-500">{@title}</dt>
      <dd class={"text-lg font-semibold font-mono #{@color_class}"}>{@value}</dd>
    </div>
    """
  end
end
