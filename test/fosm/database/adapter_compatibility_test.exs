defmodule Fosm.Database.AdapterCompatibilityTest do
  @moduledoc """
  Cross-adapter compatibility tests.

  Verifies that the application works correctly with both SQLite and PostgreSQL
  adapters, testing features that should behave consistently across adapters.

  Covers:
  - Data type compatibility (binary_id, decimal, datetime, map/json, arrays)
  - Transaction behavior
  - Query capabilities
  - Case sensitivity
  - Connection pooling
  """

  use Fosm.DataCase, async: true

  alias Fosm.{
    TransitionLog,
    AccessEvent,
    RoleAssignment,
    WebhookSubscription,
    Invoice
  }

  alias Ecto.Adapters.SQL

  describe "binary_id compatibility" do
    test "generates valid UUIDs across adapters" do
      log =
        TransitionLog.create!(%{
          record_type: "test",
          record_id: "1",
          event_name: "test",
          from_state: "a",
          to_state: "b"
        })

      # UUID should be binary
      assert is_binary(log.id)

      # PostgreSQL returns 36-char string representation, SQLite may return 16-byte binary
      # Just verify it's one of these valid formats
      uuid_size = byte_size(log.id)
      assert uuid_size in [16, 36], "UUID should be 16 bytes (binary) or 36 chars (string), got: #{uuid_size}"

      # Should be able to query by the ID
      reloaded = Fosm.Repo.get!(TransitionLog, log.id)
      assert reloaded.id == log.id
    end

    test "can query by binary_id with string conversion" do
      log =
        TransitionLog.create!(%{
          record_type: "test",
          record_id: "1",
          event_name: "test",
          from_state: "a",
          to_state: "b"
        })

      # The ID can be queried directly - Ecto handles the type conversion
      reloaded = Fosm.Repo.get!(TransitionLog, log.id)
      assert reloaded.id == log.id

      # If ID is 36 chars (string UUID format), we can cast to binary
      if byte_size(log.id) == 36 do
        # Cast string UUID to binary and back
        {:ok, binary_id} = Ecto.UUID.dump(log.id)
        {:ok, string_id} = Ecto.UUID.load(binary_id)
        assert string_id == log.id
      end
    end
  end

  describe "decimal compatibility" do
    test "stores and retrieves decimal with precision" do
      amounts = [
        Decimal.new("0.00"),
        Decimal.new("0.01"),
        Decimal.new("999999.99"),
        Decimal.new("-100.50"),
        Decimal.new("0.12345678901234567890")
      ]

      for amount <- amounts do
        invoice =
          %Invoice{}
          |> Invoice.changeset(%{
            number: "INV-#{System.unique_integer([:positive])}",
            amount: amount,
            due_date: ~D[2024-12-31]
          })
          |> Fosm.Repo.insert!()

        reloaded = Fosm.Repo.get!(Invoice, invoice.id)
        assert Decimal.equal?(reloaded.amount, amount),
               "Expected #{Decimal.to_string(amount)}, got #{Decimal.to_string(reloaded.amount)}"
      end
    end

    test "handles decimal arithmetic consistently" do
      invoice1 =
        %Invoice{}
        |> Invoice.changeset(%{
          number: "INV-001",
          amount: Decimal.new("100.00"),
          due_date: ~D[2024-12-31]
        })
        |> Fosm.Repo.insert!()

      invoice2 =
        %Invoice{}
        |> Invoice.changeset(%{
          number: "INV-002",
          amount: Decimal.new("50.00"),
          due_date: ~D[2024-12-31]
        })
        |> Fosm.Repo.insert!()

      # Sum should work correctly
      total =
        Invoice
        |> where([i], i.id in ^[invoice1.id, invoice2.id])
        |> Fosm.Repo.aggregate(:sum, :amount)

      assert Decimal.equal?(total, Decimal.new("150.00"))
    end
  end

  describe "datetime compatibility" do
    test "stores and retrieves UTC datetimes" do
      now = DateTime.utc_now()

      log =
        TransitionLog.create!(%{
          record_type: "test",
          record_id: "1",
          event_name: "test",
          from_state: "a",
          to_state: "b"
        })

      assert %DateTime{} = log.inserted_at
      assert log.inserted_at.time_zone == "Etc/UTC"

      # Should be close to current time
      diff = DateTime.diff(DateTime.utc_now(), log.inserted_at, :second)
      assert diff >= 0 && diff < 5, "Timestamp should be recent"
    end

    test "handles date fields consistently" do
      dates = [
        ~D[2024-01-01],
        ~D[2024-12-31],
        ~D[2025-06-15],
        ~D[2000-01-01],
        ~D[2099-12-31]
      ]

      for date <- dates do
        invoice =
          %Invoice{}
          |> Invoice.changeset(%{
            number: "INV-#{System.unique_integer([:positive])}",
            amount: Decimal.new("100.00"),
            due_date: date
          })
          |> Fosm.Repo.insert!()

        reloaded = Fosm.Repo.get!(Invoice, invoice.id)
        assert reloaded.due_date == date
      end
    end

    test "expiration datetime comparison works" do
      past = DateTime.add(DateTime.utc_now(), -86400, :second)
      future = DateTime.add(DateTime.utc_now(), 86400, :second)

      # Expired assignment
      expired =
        %RoleAssignment{}
        |> RoleAssignment.changeset(%{
          user_type: "Fosm.User",
          user_id: "1",
          resource_type: "Fosm.Invoice",
          role_name: "viewer",
          expires_at: past
        })
        |> Fosm.Repo.insert!()

      # Active assignment
      active =
        %RoleAssignment{}
        |> RoleAssignment.changeset(%{
          user_type: "Fosm.User",
          user_id: "2",
          resource_type: "Fosm.Invoice",
          role_name: "viewer",
          expires_at: future
        })
        |> Fosm.Repo.insert!()

      # Query active assignments
      active_count =
        RoleAssignment
        |> RoleAssignment.active()
        |> Fosm.Repo.aggregate(:count)

      assert active_count >= 1

      # The expired one should not be in active results
      refute RoleAssignment.has_role?("Fosm.User", "1", "Fosm.Invoice", nil, "viewer")
    end
  end

  describe "map/json compatibility" do
    test "stores and retrieves simple JSON objects" do
      metadata = %{"key" => "value", "number" => 42}

      log =
        TransitionLog.create!(%{
          record_type: "test",
          record_id: "1",
          event_name: "test",
          from_state: "a",
          to_state: "b",
          metadata: metadata
        })

      reloaded = Fosm.Repo.get!(TransitionLog, log.id)
      assert reloaded.metadata["key"] == "value"
      assert reloaded.metadata["number"] == 42
    end

    test "stores and retrieves nested JSON objects" do
      snapshot = %{
        "id" => 123,
        "state" => "paid",
        "metadata" => %{
          "customer" => %{"id" => 456, "name" => "Test"},
          "items" => [%{"sku" => "ABC", "qty" => 2}]
        }
      }

      log =
        TransitionLog.create!(%{
          record_type: "test",
          record_id: "1",
          event_name: "test",
          from_state: "a",
          to_state: "b",
          state_snapshot: snapshot
        })

      reloaded = Fosm.Repo.get!(TransitionLog, log.id)
      assert reloaded.state_snapshot["metadata"]["customer"]["name"] == "Test"
      assert length(reloaded.state_snapshot["metadata"]["items"]) == 1
    end

    test "handles empty maps consistently" do
      log =
        TransitionLog.create!(%{
          record_type: "test",
          record_id: "1",
          event_name: "test",
          from_state: "a",
          to_state: "b",
          metadata: %{}
        })

      reloaded = Fosm.Repo.get!(TransitionLog, log.id)
      assert reloaded.metadata == %{}
    end

    test "handles nil JSON fields consistently" do
      log =
        TransitionLog.create!(%{
          record_type: "test",
          record_id: "1",
          event_name: "test",
          from_state: "a",
          to_state: "b",
          state_snapshot: nil
        })

      reloaded = Fosm.Repo.get!(TransitionLog, log.id)
      assert is_nil(reloaded.state_snapshot)
    end
  end

  describe "array compatibility" do
    test "stores and retrieves string arrays" do
      events = ["created", "updated", "deleted"]

      subscription =
        WebhookSubscription.create!(%{
          url: "https://example.com/webhook",
          events: events
        })

      reloaded = Fosm.Repo.get!(WebhookSubscription, subscription.id)
      assert length(reloaded.events) == 3
      assert "created" in reloaded.events
      assert "updated" in reloaded.events
      assert "deleted" in reloaded.events
    end

    test "handles empty arrays consistently" do
      subscription =
        WebhookSubscription.create!(%{
          url: "https://example.com/webhook",
          events: []
        })

      reloaded = Fosm.Repo.get!(WebhookSubscription, subscription.id)
      assert reloaded.events == []
    end

    test "handles array with single element" do
      subscription =
        WebhookSubscription.create!(%{
          url: "https://example.com/webhook",
          events: ["pay"]
        })

      reloaded = Fosm.Repo.get!(WebhookSubscription, subscription.id)
      assert reloaded.events == ["pay"]
    end
  end

  describe "transaction behavior" do
    test "commits transactions consistently" do
      {:ok, result} =
        Fosm.Repo.transaction(fn ->
          log =
            TransitionLog.create!(%{
              record_type: "test",
              record_id: "txn-1",
              event_name: "test",
              from_state: "a",
              to_state: "b"
            })

          event =
            AccessEvent.create!(%{
              action: "grant",
              user_type: "Fosm.User",
              user_id: "txn-user",
              resource_type: "Fosm.Invoice",
              role_name: "owner",
              result: "allowed"
            })

          {log, event}
        end)

      {log, event} = result

      # Both should be committed
      assert Fosm.Repo.get(TransitionLog, log.id)
      assert Fosm.Repo.get(AccessEvent, event.id)
    end

    test "rolls back transactions on error" do
      assert_raise RuntimeError, fn ->
        Fosm.Repo.transaction(fn ->
          log =
            TransitionLog.create!(%{
              record_type: "test",
              record_id: "txn-rollback",
              event_name: "test",
              from_state: "a",
              to_state: "b"
            })

          # This should cause rollback
          raise "Intentional error"
        end)
      end

      # Verify log was not created
      count =
        TransitionLog
        |> where([l], l.record_id == "txn-rollback")
        |> Fosm.Repo.aggregate(:count)

      assert count == 0
    end
  end

  describe "query capabilities" do
    test "where clauses work consistently" do
      # Create test records
      for i <- 1..5 do
        TransitionLog.create!(%{
          record_type: "query_test",
          record_id: "#{i}",
          event_name: if(rem(i, 2) == 0, do: "even", else: "odd"),
          from_state: "a",
          to_state: "b"
        })
      end

      # Query with where clause
      even_logs =
        TransitionLog
        |> where([l], l.record_type == "query_test")
        |> where([l], l.event_name == "even")
        |> Fosm.Repo.all()

      assert length(even_logs) == 2
    end

    test "order_by works consistently" do
      # Use named test data to avoid conflicts with other tests
      test_prefix = "order_test_#{System.unique_integer([:positive])}"

      for i <- 1..3 do
        TransitionLog.create!(%{
          record_type: test_prefix,
          record_id: "#{i}",
          event_name: "test",
          from_state: "a",
          to_state: "b"
        })

        # Small delay to ensure different timestamps
        Process.sleep(50)
      end

      # Order by inserted_at descending
      logs =
        TransitionLog
        |> where([l], l.record_type == ^test_prefix)
        |> order_by(desc: :inserted_at)
        |> Fosm.Repo.all()

      assert length(logs) == 3
      # Most recent should be first (highest record_id)
      [first | rest] = logs
      [second | _] = rest

      # Verify descending order - each timestamp should be >= the next one
      assert DateTime.compare(first.inserted_at, second.inserted_at) in [:gt, :eq]
    end

    test "limit works consistently" do
      for i <- 1..10 do
        TransitionLog.create!(%{
          record_type: "limit_test",
          record_id: "#{i}",
          event_name: "test",
          from_state: "a",
          to_state: "b"
        })
      end

      logs =
        TransitionLog
        |> where([l], l.record_type == "limit_test")
        |> limit(5)
        |> Fosm.Repo.all()

      assert length(logs) == 5
    end

    test "aggregate functions work consistently" do
      for i <- 1..5 do
        TransitionLog.create!(%{
          record_type: "agg_test",
          record_id: "#{i}",
          event_name: "test",
          from_state: "a",
          to_state: "b"
        })
      end

      count =
        TransitionLog
        |> where([l], l.record_type == "agg_test")
        |> Fosm.Repo.aggregate(:count)

      assert count == 5
    end
  end

  describe "string handling" do
    test "handles unicode strings consistently" do
      unicode_strings = [
        "Hello World",
        "日本語テスト",
        "🚀 Emojis work",
        "München Café",
        "العربية"
      ]

      for str <- unicode_strings do
        log =
          TransitionLog.create!(%{
            record_type: str,
            record_id: "1",
            event_name: "test",
            from_state: "a",
            to_state: "b"
          })

        reloaded = Fosm.Repo.get!(TransitionLog, log.id)
        assert reloaded.record_type == str
      end
    end

    test "handles long strings consistently within column limits" do
      # record_id has a 255 character limit in the migration
      long_string = String.duplicate("a", 255)

      log =
        TransitionLog.create!(%{
          record_type: "test",
          record_id: long_string,
          event_name: "test",
          from_state: "a",
          to_state: "b"
        })

      reloaded = Fosm.Repo.get!(TransitionLog, log.id)
      assert reloaded.record_id == long_string
    end

    test "handles unicode in metadata fields" do
      # metadata field (map/json) doesn't have length limits
      unicode_data = %{"long_text" => String.duplicate("日本語", 100)}

      log =
        TransitionLog.create!(%{
          record_type: "test",
          record_id: "1",
          event_name: "test",
          from_state: "a",
          to_state: "b",
          metadata: unicode_data
        })

      reloaded = Fosm.Repo.get!(TransitionLog, log.id)
      assert reloaded.metadata["long_text"] == unicode_data["long_text"]
    end
  end

  describe "adapter detection" do
    test "can detect current adapter" do
      adapter = Fosm.Repo.__adapter__()

      assert adapter in [Ecto.Adapters.Postgres, Ecto.Adapters.SQLite3]

      # Verify we can identify which one
      is_postgres = adapter == Ecto.Adapters.Postgres
      is_sqlite = adapter == Ecto.Adapters.SQLite3

      assert is_postgres or is_sqlite
    end

    test "adapter supports required features" do
      adapter = Fosm.Repo.__adapter__()

      # Test basic query
      result = SQL.query!(Fosm.Repo, "SELECT 1 as test")
      assert result.rows == [[1]]

      # Test parameterized query
      result = SQL.query!(Fosm.Repo, "SELECT $1::text as val", ["hello"])
      assert result.rows == [["hello"]]
    end
  end

  describe "concurrent access" do
    @desc "Note: Concurrent access tests may be limited by Ecto sandbox mode"
    test "handles concurrent reads consistently", %{async: async?} do
      # Skip detailed concurrent tests in sync sandbox mode
      # The sandbox restricts cross-process access

      # Create a record
      log =
        TransitionLog.create!(%{
          record_type: "concurrent_test",
          record_id: "1",
          event_name: "test",
          from_state: "a",
          to_state: "b"
        })

      if async? do
        # In async mode, we can test concurrent access
        # Allow sandbox access for this process
        parent = self()

        tasks =
          for _ <- 1..3 do
            Task.async(fn ->
              # Share connection with task
              Ecto.Adapters.SQL.Sandbox.allow(Fosm.Repo, parent, self())
              Fosm.Repo.get(TransitionLog, log.id)
            end)
          end

        results = Task.await_many(tasks, 5000)

        # All should get the same result
        for result <- results do
          assert result != nil
          assert result.id == log.id
        end
      else
        # In sync mode, just verify the record exists
        result = Fosm.Repo.get(TransitionLog, log.id)
        assert result.id == log.id
      end
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  # No additional helpers needed - using DataCase imports
end
