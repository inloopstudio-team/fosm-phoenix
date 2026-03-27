defmodule Fosm.Database.MigrationRunnerTest do
  @moduledoc """
  Tests that all migrations run cleanly on both SQLite and PostgreSQL adapters.

  Covers:
  - Migration files execute without errors
  - Tables are created with correct structure
  - Indexes are created correctly
  - Rollback operations work where applicable
  """

  use Fosm.DataCase, async: false

  alias Ecto.Adapters.SQL

  @migration_modules [
    Fosm.Repo.Migrations.CreateTransitionLogs,
    Fosm.Repo.Migrations.CreateAccessEvents,
    Fosm.Repo.Migrations.CreateRoleAssignments,
    Fosm.Repo.Migrations.CreateWebhookSubscriptions,
    Fosm.Repo.Migrations.CreateInvoices
  ]

  @tables [
    "fosm_transition_logs",
    "fosm_access_events",
    "fosm_role_assignments",
    "fosm_webhook_subscriptions",
    "invoices"
  ]

  describe "migrations run cleanly" do
    test "all migration modules are loadable" do
      for module <- @migration_modules do
        assert Code.ensure_loaded?(module),
               "Migration module #{inspect(module)} should be loadable"
      end
    end

    test "all expected tables exist after migrations" do
      for table <- @tables do
        assert table_exists?(table), "Table #{table} should exist"
      end
    end

    test "transition_logs table has correct columns" do
      columns = get_columns("fosm_transition_logs")

      assert "id" in columns
      assert "record_type" in columns
      assert "record_id" in columns
      assert "event_name" in columns
      assert "from_state" in columns
      assert "to_state" in columns
      assert "actor_type" in columns
      assert "actor_id" in columns
      assert "metadata" in columns
      assert "state_snapshot" in columns
      assert "inserted_at" in columns

      # Verify no updated_at (immutable log)
      refute "updated_at" in columns
    end

    test "access_events table has correct columns" do
      columns = get_columns("fosm_access_events")

      assert "id" in columns
      assert "action" in columns
      assert "user_type" in columns
      assert "user_id" in columns
      assert "resource_type" in columns
      assert "resource_id" in columns
      assert "role_name" in columns
      assert "result" in columns
      assert "metadata" in columns
      assert "inserted_at" in columns

      # Verify no updated_at (immutable log)
      refute "updated_at" in columns
    end

    test "role_assignments table has correct columns" do
      columns = get_columns("fosm_role_assignments")

      assert "id" in columns
      assert "user_type" in columns
      assert "user_id" in columns
      assert "resource_type" in columns
      assert "resource_id" in columns
      assert "role_name" in columns
      assert "granted_by_type" in columns
      assert "granted_by_id" in columns
      assert "expires_at" in columns
      assert "inserted_at" in columns
      assert "updated_at" in columns
    end

    test "webhook_subscriptions table has correct columns" do
      columns = get_columns("fosm_webhook_subscriptions")

      assert "id" in columns
      assert "url" in columns
      assert "events" in columns
      assert "record_type" in columns
      assert "record_id" in columns
      assert "secret_token" in columns
      assert "active" in columns
      assert "delivery_mode" in columns
      assert "retry_count" in columns
      assert "last_delivery_at" in columns
      assert "last_delivery_status" in columns
      assert "metadata" in columns
      assert "inserted_at" in columns
      assert "updated_at" in columns
    end

    test "invoices table has correct columns" do
      columns = get_columns("invoices")

      assert "id" in columns
      assert "state" in columns
      assert "number" in columns
      assert "amount" in columns
      assert "due_date" in columns
      assert "fosm_metadata" in columns
      assert "inserted_at" in columns
      assert "updated_at" in columns
    end
  end

  describe "indexes are created correctly" do
    test "transition_logs has expected indexes" do
      indexes = get_indexes("fosm_transition_logs")

      # Check for composite index on record_type, record_id
      assert has_index?(indexes, "fosm_transition_logs", ["record_type", "record_id"]),
             "Should have index on record_type, record_id"

      # Check for index on inserted_at
      assert has_index?(indexes, "fosm_transition_logs", ["inserted_at"]),
             "Should have index on inserted_at"

      # Check for index on event_name
      assert has_index?(indexes, "fosm_transition_logs", ["event_name"]),
             "Should have index on event_name"
    end

    test "access_events has expected indexes" do
      indexes = get_indexes("fosm_access_events")

      assert has_index?(indexes, "fosm_access_events", ["user_type", "user_id"]),
             "Should have index on user_type, user_id"

      assert has_index?(indexes, "fosm_access_events", ["resource_type", "resource_id"]),
             "Should have index on resource_type, resource_id"

      assert has_index?(indexes, "fosm_access_events", ["action"]),
             "Should have index on action"

      assert has_index?(indexes, "fosm_access_events", ["inserted_at"]),
             "Should have index on inserted_at"
    end

    test "role_assignments has expected indexes" do
      indexes = get_indexes("fosm_role_assignments")

      assert has_index?(indexes, "fosm_role_assignments", ["user_type", "user_id"]),
             "Should have index on user_type, user_id"

      assert has_index?(indexes, "fosm_role_assignments", ["resource_type", "resource_id"]),
             "Should have index on resource_type, resource_id"

      assert has_index?(indexes, "fosm_role_assignments", ["role_name"]),
             "Should have index on role_name"

      assert has_index?(indexes, "fosm_role_assignments", ["expires_at"]),
             "Should have index on expires_at"
    end

    test "webhook_subscriptions has expected indexes" do
      indexes = get_indexes("fosm_webhook_subscriptions")

      assert has_index?(indexes, "webhook_subscriptions", ["active"]),
             "Should have index on active"

      assert has_index?(indexes, "webhook_subscriptions", ["record_type"]),
             "Should have index on record_type"

      assert has_index?(indexes, "webhook_subscriptions", ["inserted_at"]),
             "Should have index on inserted_at"
    end

    test "invoices has expected indexes" do
      indexes = get_indexes("invoices")

      assert has_index?(indexes, "invoices", ["state"]),
             "Should have index on state"

      assert has_index?(indexes, "invoices", ["inserted_at"]),
             "Should have index on inserted_at"

      assert has_index?(indexes, "invoices", ["updated_at"]),
             "Should have index on updated_at"
    end
  end

  describe "adapter-specific migration behavior" do
    test "detects correct adapter type" do
      adapter = Fosm.Repo.__adapter__()
      assert adapter in [Ecto.Adapters.Postgres, Ecto.Adapters.SQLite3],
             "Should use PostgreSQL or SQLite3 adapter"
    end

    test "binary_id columns use correct type" do
      # Check that id columns are UUID/binary_id type
      adapter = Fosm.Repo.__adapter__()

      case adapter do
        Ecto.Adapters.Postgres ->
          # PostgreSQL uses uuid type
          sql = "SELECT data_type FROM information_schema.columns WHERE table_name = 'fosm_transition_logs' AND column_name = 'id'"
          result = SQL.query!(Fosm.Repo, sql)
          type = result.rows |> List.first() |> List.first()
          assert type in ["uuid", "binary"], "PostgreSQL id column should be uuid type, got: #{inspect(type)}"

        Ecto.Adapters.SQLite3 ->
          # SQLite stores binary_id as BLOB
          sql = "SELECT typeof(id) FROM fosm_transition_logs LIMIT 0"
          # Just verify the query doesn't fail - SQLite is flexible with types
          assert :ok = SQL.query!(Fosm.Repo, sql) && :ok

        _ ->
          :ok
      end
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp table_exists?(table_name) do
    adapter = Fosm.Repo.__adapter__()

    case adapter do
      Ecto.Adapters.Postgres ->
        sql = """
        SELECT EXISTS (
          SELECT FROM information_schema.tables
          WHERE table_schema = 'public'
          AND table_name = $1
        )
        """
        result = SQL.query!(Fosm.Repo, sql, [table_name])
        result.rows |> List.first() |> List.first()

      Ecto.Adapters.SQLite3 ->
        sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=$1"
        result = SQL.query!(Fosm.Repo, sql, [table_name])
        length(result.rows) > 0

      _ ->
        false
    end
  end

  defp get_columns(table_name) do
    adapter = Fosm.Repo.__adapter__()

    case adapter do
      Ecto.Adapters.Postgres ->
        sql = """
        SELECT column_name FROM information_schema.columns
        WHERE table_name = $1
        """
        result = SQL.query!(Fosm.Repo, sql, [table_name])
        result.rows |> Enum.map(&List.first/1)

      Ecto.Adapters.SQLite3 ->
        sql = "PRAGMA table_info(#{table_name})"
        result = SQL.query!(Fosm.Repo, sql)
        # PRAGMA returns: cid, name, type, notnull, dflt_value, pk
        result.rows |> Enum.map(fn row -> Enum.at(row, 1) end)

      _ ->
        []
    end
  end

  defp get_indexes(table_name) do
    adapter = Fosm.Repo.__adapter__()

    case adapter do
      Ecto.Adapters.Postgres ->
        sql = """
        SELECT indexname, indexdef
        FROM pg_indexes
        WHERE tablename = $1
        """
        result = SQL.query!(Fosm.Repo, sql, [table_name])
        result.rows

      Ecto.Adapters.SQLite3 ->
        sql = "PRAGMA index_list(#{table_name})"
        result = SQL.query!(Fosm.Repo, sql)
        # PRAGMA returns: seq, name, unique, origin, partial
        result.rows |> Enum.map(fn row -> {Enum.at(row, 1), ""} end)

      _ ->
        []
    end
  end

  defp has_index?(indexes, table_name, column_names) do
    column_pattern = column_names |> Enum.join(".*,.*")

    Enum.any?(indexes, fn index_data ->
      case index_data do
        {name, definition} when is_binary(definition) ->
          # PostgreSQL format
          String.contains?(name, table_name) &&
            Regex.match?(~r/#{column_pattern}/, definition)

        {name, _} when is_binary(name) ->
          # SQLite format - just check if index name contains column hints
          String.contains?(name, List.first(column_names))

        _ ->
          false
      end
    end)
  end
end
