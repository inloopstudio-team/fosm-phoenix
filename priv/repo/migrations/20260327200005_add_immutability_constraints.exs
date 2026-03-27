defmodule Fosm.Repo.Migrations.AddImmutabilityConstraints do
  @moduledoc """
  Adds database-level immutability constraints to audit tables.

  TransitionLog and AccessEvent should never be updated or deleted.
  These constraints enforce that at the database level.

  Note: These are PostgreSQL-specific. For other databases, 
  application-level enforcement is used.
  """
  use Ecto.Migration

  def up do
    # Create trigger function to prevent updates on transition_logs
    execute("""
    CREATE OR REPLACE FUNCTION prevent_transition_log_update()
    RETURNS TRIGGER AS $$
    BEGIN
      RAISE EXCEPTION 'TransitionLog records are immutable and cannot be updated';
    END;
    $$ LANGUAGE plpgsql;
    """)

    # Create trigger function to prevent deletes on transition_logs
    execute("""
    CREATE OR REPLACE FUNCTION prevent_transition_log_delete()
    RETURNS TRIGGER AS $$
    BEGIN
      RAISE EXCEPTION 'TransitionLog records are immutable and cannot be deleted';
    END;
    $$ LANGUAGE plpgsql;
    """)

    # Create trigger function to prevent updates on access_events
    execute("""
    CREATE OR REPLACE FUNCTION prevent_access_event_update()
    RETURNS TRIGGER AS $$
    BEGIN
      RAISE EXCEPTION 'AccessEvent records are immutable and cannot be updated';
    END;
    $$ LANGUAGE plpgsql;
    """)

    # Create trigger function to prevent deletes on access_events
    execute("""
    CREATE OR REPLACE FUNCTION prevent_access_event_delete()
    RETURNS TRIGGER AS $$
    BEGIN
      RAISE EXCEPTION 'AccessEvent records are immutable and cannot be deleted';
    END;
    $$ LANGUAGE plpgsql;
    """)

    # Apply triggers to transition_logs
    execute("""
    CREATE TRIGGER transition_logs_no_update
      BEFORE UPDATE ON fosm_transition_logs
      FOR EACH ROW
      EXECUTE FUNCTION prevent_transition_log_update();
    """)

    execute("""
    CREATE TRIGGER transition_logs_no_delete
      BEFORE DELETE ON fosm_transition_logs
      FOR EACH ROW
      EXECUTE FUNCTION prevent_transition_log_delete();
    """)

    # Apply triggers to access_events
    execute("""
    CREATE TRIGGER access_events_no_update
      BEFORE UPDATE ON fosm_access_events
      FOR EACH ROW
      EXECUTE FUNCTION prevent_access_event_update();
    """)

    execute("""
    CREATE TRIGGER access_events_no_delete
      BEFORE DELETE ON fosm_access_events
      FOR EACH ROW
      EXECUTE FUNCTION prevent_access_event_delete();
    """)
  end

  def down do
    # Remove triggers
    execute("DROP TRIGGER IF EXISTS transition_logs_no_update ON fosm_transition_logs;")
    execute("DROP TRIGGER IF EXISTS transition_logs_no_delete ON fosm_transition_logs;")
    execute("DROP TRIGGER IF EXISTS access_events_no_update ON fosm_access_events;")
    execute("DROP TRIGGER IF EXISTS access_events_no_delete ON fosm_access_events;")

    # Remove functions
    execute("DROP FUNCTION IF EXISTS prevent_transition_log_update();")
    execute("DROP FUNCTION IF EXISTS prevent_transition_log_delete();")
    execute("DROP FUNCTION IF EXISTS prevent_access_event_update();")
    execute("DROP FUNCTION IF EXISTS prevent_access_event_delete();")
  end
end
