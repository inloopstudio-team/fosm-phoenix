defmodule FosmTest do
  use ExUnit.Case, async: true

  test "config returns default values" do
    config = Fosm.config()
    assert is_map(config)
    assert Map.has_key?(config, :repo)
    assert Map.has_key?(config, :transition_log_strategy)
  end

  test "config/2 returns specific value" do
    assert Fosm.config(:transition_log_strategy) == :sync
  end

  test "config/2 returns default when key not found" do
    assert Fosm.config(:non_existent, :default) == :default
  end
end
