defmodule Fosm.Errors do
  @moduledoc """
  Custom exceptions for FOSM lifecycle operations.
  """

  # ============================================================================
  # Access Control Errors
  # ============================================================================

  defmodule AccessDenied do
    @moduledoc """
    Raised when an actor lacks permission to perform an action.
    """
    defexception [
      :action,
      :resource_type,
      :resource_id,
      :actor,
      :roles,
      :reason,
      plug_status: 403
    ]

    def message(exception) do
      "Access denied: #{exception.reason || "Actor cannot perform '#{exception.action}' on #{exception.resource_type}:#{exception.resource_id}"}"
    end
  end

  # ============================================================================
  # State Transition Errors
  # ============================================================================

  defmodule TerminalState do
    @moduledoc """
    Raised when attempting to transition from a terminal state.
    """
    defexception [:state, :module, plug_status: 422]

    def message(exception) do
      "State '#{exception.state}' is terminal and cannot transition further"
    end
  end

  defmodule InvalidTransition do
    @moduledoc """
    Raised when attempting an invalid state transition.
    """
    defexception [:event, :from, :module, plug_status: 422]

    def message(exception) do
      "Cannot fire '#{exception.event}' from state '#{exception.from}'"
    end
  end

  defmodule GuardFailed do
    @moduledoc """
    Raised when a lifecycle guard check fails.
    """
    defexception [:guard, :event, :reason, plug_status: 422]

    def message(exception) do
      base = "Guard '#{exception.guard}' failed"
      if exception.reason, do: "#{base}: #{exception.reason}", else: base
    end
  end
end
