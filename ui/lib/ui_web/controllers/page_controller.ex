defmodule GitUIWeb.PageController do
  use GitUIWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
