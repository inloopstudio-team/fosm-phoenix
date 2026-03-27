defmodule Fosm.ConfigurationTest do
  @moduledoc """
  Tests for FOSM configuration module.

  Verifies configuration defaults, retrieval, and runtime updates.
  """
  use ExUnit.Case, async: true

  alias Fosm

  describe "config/0" do
    test "returns configuration as a map" do
      config = Fosm.config()
      assert is_map(config)
    end

    test "includes default values" do
      config = Fosm.config()

      assert Map.has_key?(config, :repo)
      assert Map.has_key?(config, :transition_log_strategy)
      assert Map.has_key?(config, :enable_webhooks)
      assert Map.has_key?(config, :webhook_secret_header)
      assert Map.has_key?(config, :default_oban_queue)
      assert Map.has_key?(config, :transition_buffer_interval_ms)
      assert Map.has_key?(config, :transition_buffer_max_size)
      assert Map.has_key?(config, :rbac_cache_ttl_seconds)
    end

    test "default repo is nil" do
      config = Fosm.config()
      assert config.repo == nil
    end

    test "default transition_log_strategy is :sync" do
      config = Fosm.config()
      assert config.transition_log_strategy == :sync
    end

    test "default enable_webhooks is false" do
      config = Fosm.config()
      assert config.enable_webhooks == false
    end

    test "default webhook_secret_header is set" do
      config = Fosm.config()
      assert config.webhook_secret_header == "X-FOSM-Signature"
    end

    test "default oban_queue is :default" do
      config = Fosm.config()
      assert config.default_oban_queue == :default
    end

    test "default buffer interval is 1000ms" do
      config = Fosm.config()
      assert config.transition_buffer_interval_ms == 1000
    end

    test "default buffer max size is 100" do
      config = Fosm.config()
      assert config.transition_buffer_max_size == 100
    end

    test "default rbac cache ttl is 300 seconds" do
      config = Fosm.config()
      assert config.rbac_cache_ttl_seconds == 300
    end
  end

  describe "config/1" do
    test "retrieves specific configuration value" do
      assert Fosm.config(:transition_log_strategy) == :sync
    end

    test "returns nil for unknown key" do
      assert Fosm.config(:unknown_key) == nil
    end

    test "returns default for unknown key when provided" do
      assert Fosm.config(:unknown_key, :default_value) == :default_value
    end
  end

  describe "put_config/2" do
    test "updates configuration at runtime" do
      original = Fosm.config(:transition_log_strategy)

      try do
        Fosm.put_config(:transition_log_strategy, :async_job)
        assert Fosm.config(:transition_log_strategy) == :async_job
      after
        # Restore original
        Fosm.put_config(:transition_log_strategy, original)
      end
    end

    test "persists configuration across calls" do
      original = Fosm.config(:test_key)

      try do
        Fosm.put_config(:test_key, "test_value")
        assert Fosm.config(:test_key) == "test_value"

        # Verify it persists in subsequent calls
        assert Fosm.config(:test_key) == "test_value"
      after
        # Clean up
        if original do
          Fosm.put_config(:test_key, original)
        else
          # Remove the key by setting to nil
          current = Application.get_env(:fosm, Fosm, [])
          Application.put_env(:fosm, Fosm, Keyword.delete(current, :test_key))
        end
      end
    end
  end

  describe "configuration merging" do
    test "application env overrides defaults" do
      # This test verifies that if we set values in Application env,
      # they override the defaults
      original = Application.get_env(:fosm, Fosm, [])

      try do
        Application.put_env(:fosm, Fosm, [
          transition_log_strategy: :buffer,
          enable_webhooks: true
        ])

        config = Fosm.config()
        assert config.transition_log_strategy == :buffer
        assert config.enable_webhooks == true
      after
        Application.put_env(:fosm, Fosm, original)
      end
    end
  end
end
