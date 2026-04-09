defmodule GitUIWeb.Router do
  use GitUIWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GitUIWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", GitUIWeb do
    pipe_through :browser

    live "/", DashboardLive
    live "/log", LogLive
    live "/branches", BranchesLive
    live "/diff", DiffLive
    live "/blame/:path", BlameLive
  end
end
