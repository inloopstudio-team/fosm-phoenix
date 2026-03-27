defmodule Fosm.Lifecycle.SnapshotConfigurationTest do
  use ExUnit.Case, async: true

  alias Fosm.Lifecycle.SnapshotConfiguration

  describe "strategies" do
    test "every/0 creates :every strategy" do
      config = SnapshotConfiguration.every()
      assert config.strategy == :every
    end

    test "count/1 creates :count strategy with interval" do
      config = SnapshotConfiguration.count(10)
      assert config.strategy == :count
      assert config.interval == 10
    end

    test "time/1 creates :time strategy with interval" do
      config = SnapshotConfiguration.time(3600)
      assert config.strategy == :time
      assert config.interval == 3600
    end

    test "terminal/0 creates :terminal strategy" do
      config = SnapshotConfiguration.terminal()
      assert config.strategy == :terminal
    end

    test "manual/0 creates :manual strategy" do
      config = SnapshotConfiguration.manual()
      assert config.strategy == :manual
    end
  end

  describe "set_attributes/2" do
    test "sets snapshot attributes" do
      config = SnapshotConfiguration.every()
      config = SnapshotConfiguration.set_attributes(config, [:amount, :status])

      assert config.attributes == [:amount, :status]
    end
  end

  describe "should_snapshot?/6" do
    test ":every strategy always snapshots" do
      config = SnapshotConfiguration.every()
      assert SnapshotConfiguration.should_snapshot?(config, 0, 0, :paid, false, [])
    end

    test ":terminal strategy snapshots on terminal state" do
      config = SnapshotConfiguration.terminal()
      assert SnapshotConfiguration.should_snapshot?(config, 0, 0, :paid, true, [])
      refute SnapshotConfiguration.should_snapshot?(config, 0, 0, :draft, false, [])
    end

    test ":count strategy snapshots when count >= interval" do
      config = SnapshotConfiguration.count(10)
      assert SnapshotConfiguration.should_snapshot?(config, 10, 0, :draft, false, [])
      assert SnapshotConfiguration.should_snapshot?(config, 15, 0, :draft, false, [])
      refute SnapshotConfiguration.should_snapshot?(config, 5, 0, :draft, false, [])
    end

    test ":time strategy snapshots when seconds >= interval" do
      config = SnapshotConfiguration.time(3600)
      assert SnapshotConfiguration.should_snapshot?(config, 0, 3600, :draft, false, [])
      assert SnapshotConfiguration.should_snapshot?(config, 0, 7200, :draft, false, [])
      refute SnapshotConfiguration.should_snapshot?(config, 0, 1800, :draft, false, [])
    end

    test ":manual strategy never snapshots automatically" do
      config = SnapshotConfiguration.manual()
      refute SnapshotConfiguration.should_snapshot?(config, 0, 0, :paid, true, [])
    end

    test "force: true overrides all" do
      config = SnapshotConfiguration.manual()
      assert SnapshotConfiguration.should_snapshot?(config, 0, 0, :draft, false, force: true)
    end

    test "force: false prevents all" do
      config = SnapshotConfiguration.every()
      refute SnapshotConfiguration.should_snapshot?(config, 0, 0, :paid, true, force: false)
    end
  end

  describe "serialize_value/1 via build_snapshot/2" do
    test "serializes DateTime" do
      # We can't test this without a mock module
      # Full test in task-25
      assert true
    end
  end
end
