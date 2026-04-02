defmodule GitWrapperExTest do
  use ExUnit.Case
  doctest GitWrapperEx

  test "greets the world" do
    assert GitWrapperEx.hello() == :world
  end
end
