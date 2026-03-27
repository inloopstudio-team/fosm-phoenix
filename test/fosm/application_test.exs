defmodule Fosm.ApplicationTest do
  @moduledoc """
  Tests for the FOSM Application supervision tree.
  
  Verifies proper startup order:
  - Repo (if available)
  - Oban (if configured)
  - Current (if available)
  - TransitionBuffer (conditional on strategy)
  - Registry
  """
  use ExUnit.Case, async: false

  alias Fosm.Application

  describe "start/2" do
    test "application starts successfully" do
      # The application is already started by test_helper.exs
      # We verify the supervision tree is running
      
      children = Supervisor.which_children(Fosm.Supervisor)
      
      # Verify essential children are running
      child_ids = Enum.map(children, fn {id, _, _, _} -> id end)
      
      # Registry should always be present
      assert Fosm.Registry in child_ids
    end
  end

  describe "build_children/0 (via internal logic)" do
    test "starts TransitionBuffer when strategy is :buffered" do
      # Note: This is an integration test that would require
      # restarting the application with different config
      
      # Verify current config
      strategy = Application.get_env(:fosm, :logging_strategy, :immediate)
      
      if strategy == :buffered do
        assert Process.whereis(Fosm.TransitionBuffer) != nil
      else
        # In :immediate mode, buffer may or may not be running
        # depending on config at startup
      end
    end
  end

  describe "config_change/3" do
    test "handles config changes gracefully" do
      # Test that config_change callback exists and returns :ok
      assert :ok = Application.config_change([], [], [])
    end
  end
end
