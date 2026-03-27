defmodule Fosm.Jobs.TransitionLogJobTest do
  @moduledoc """
  Tests for the TransitionLogJob Oban worker.
  
  These tests use Oban.Testing mode to verify:
  - Job enqueueing
  - Job execution with valid data
  - Error handling for invalid data
  - Retry behavior
  """
  use Fosm.DataCase, async: true
  use Oban.Testing, repo: Fosm.Repo

  import Fosm.Factory

  alias Fosm.Jobs.TransitionLogJob
  alias Fosm.TransitionLog

  describe "perform/1" do
    test "successfully creates a transition log from job args" do
      log_data = %{
        record_type: "Invoice",
        record_id: "123",
        event_name: "send",
        from_state: "draft",
        to_state: "sent",
        actor_type: "Fosm.User",
        actor_id: "1",
        metadata: %{ip: "127.0.0.1"}
      }

      job = %Oban.Job{args: log_data, attempt: 1}
      
      assert :ok = TransitionLogJob.perform(job)
      
      # Verify log was created
      log = Repo.get_by(TransitionLog, record_id: "123", event_name: "send")
      assert log != nil
      assert log.from_state == "draft"
      assert log.to_state == "sent"
    end

    test "handles string keys in args" do
      log_data = %{
        "record_type" => "Invoice",
        "record_id" => "456",
        "event_name" => "pay",
        "from_state" => "sent",
        "to_state" => "paid",
        "actor_type" => "Fosm.User",
        "actor_id" => "2"
      }

      job = %Oban.Job{args: log_data, attempt: 1}
      
      assert :ok = TransitionLogJob.perform(job)
      
      log = Repo.get_by(TransitionLog, record_id: "456")
      assert log != nil
      assert log.event_name == "pay"
    end

    test "handles nested maps in metadata" do
      log_data = %{
        record_type: "Invoice",
        record_id: "789",
        event_name: "cancel",
        from_state: "draft",
        to_state: "cancelled",
        metadata: %{
          reason: "customer_request",
          details: %{
            request_id: "req_123"
          }
        }
      }

      job = %Oban.Job{args: log_data, attempt: 1}
      
      assert :ok = TransitionLogJob.perform(job)
      
      log = Repo.get_by(TransitionLog, record_id: "789")
      assert log.metadata["reason"] == "customer_request"
    end

    test "gracefully handles validation errors" do
      # Missing required field
      log_data = %{
        record_type: "Invoice"
        # Missing record_id and other required fields
      }

      job = %Oban.Job{args: log_data, attempt: 1}
      
      # Should return error tuple, not crash
      assert {:error, _changeset} = TransitionLogJob.perform(job)
    end

    test "includes actor_label when provided" do
      log_data = %{
        record_type: "Invoice",
        record_id: "999",
        event_name: "process",
        actor_type: "symbol",
        actor_label: "background_job"
      }

      job = %Oban.Job{args: log_data, attempt: 1}
      
      assert :ok = TransitionLogJob.perform(job)
      
      log = Repo.get_by(TransitionLog, record_id: "999")
      assert log.actor_label == "background_job"
    end
  end

  describe "backoff/1" do
    test "returns exponential backoff" do
      assert TransitionLogJob.backoff(%Oban.Job{attempt: 1}) == :timer.seconds(2)
      assert TransitionLogJob.backoff(%Oban.Job{attempt: 2}) == :timer.seconds(4)
      assert TransitionLogJob.backoff(%Oban.Job{attempt: 3}) == :timer.seconds(8)
      assert TransitionLogJob.backoff(%Oban.Job{attempt: 4}) == :timer.seconds(16)
    end
  end

  describe "enqueueing" do
    test "can be enqueued with perform_later" do
      log_data = %{
        record_type: "Invoice",
        record_id: "111",
        event_name: "send"
      }

      assert {:ok, job} = Oban.insert(TransitionLogJob.new(log_data))
      assert job.queue == "fosm_logs"
      assert job.state == "available"
    end

    test "respects priority settings" do
      log_data = %{record_type: "Invoice", record_id: "222", event_name: "pay"}
      
      {:ok, job} = Oban.insert(TransitionLogJob.new(log_data))
      assert job.priority == 1
    end
  end
end
