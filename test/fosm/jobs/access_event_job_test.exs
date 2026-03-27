defmodule Fosm.Jobs.AccessEventJobTest do
  @moduledoc """
  Tests for the AccessEventJob Oban worker.
  
  These tests verify:
  - Successful creation of access events
  - Normalization of string/atom keys
  - Result normalization (allowed/denied)
  - Error handling
  """
  use Fosm.DataCase, async: true
  use Oban.Testing, repo: Fosm.Repo

  import Fosm.Factory

  alias Fosm.Jobs.AccessEventJob
  alias Fosm.AccessEvent

  describe "perform/1" do
    test "creates access event for allowed action" do
      event_data = %{
        actor_id: 1,
        actor_type: "Fosm.User",
        action: "read",
        resource_type: "Invoice",
        resource_id: 123,
        result: "allowed"
      }

      job = %Oban.Job{args: event_data, attempt: 1}
      
      assert :ok = AccessEventJob.perform(job)
      
      event = Repo.get_by(AccessEvent, resource_id: 123, action: "read")
      assert event != nil
      assert event.result == :allowed
    end

    test "creates access event for denied action" do
      event_data = %{
        actor_id: 1,
        actor_type: "Fosm.User",
        action: "delete",
        resource_type: "Invoice",
        resource_id: 456,
        result: "denied",
        reason: "insufficient_permissions"
      }

      job = %Oban.Job{args: event_data, attempt: 1}
      
      assert :ok = AccessEventJob.perform(job)
      
      event = Repo.get_by(AccessEvent, resource_id: 456, action: "delete")
      assert event != nil
      assert event.result == :denied
      assert event.reason == "insufficient_permissions"
    end

    test "handles string keys in args" do
      event_data = %{
        "actor_id" => 2,
        "actor_type" => "Fosm.User",
        "action" => "update",
        "resource_type" => "Invoice",
        "resource_id" => 789,
        "result" => "allowed",
        "metadata" => %{"ip" => "192.168.1.1"}
      }

      job = %Oban.Job{args: event_data, attempt: 1}
      
      assert :ok = AccessEventJob.perform(job)
      
      event = Repo.get_by(AccessEvent, resource_id: 789)
      assert event.actor_id == 2
      assert event.metadata["ip"] == "192.168.1.1"
    end

    test "normalizes atom result values" do
      event_data = %{
        actor_id: 3,
        actor_type: "Fosm.User",
        action: "pay",
        resource_type: "Invoice",
        resource_id: 999,
        result: :denied  # Atom instead of string
      }

      job = %Oban.Job{args: event_data, attempt: 1}
      
      assert :ok = AccessEventJob.perform(job)
      
      event = Repo.get_by(AccessEvent, resource_id: 999)
      assert event.result == :denied
    end

    test "handles anonymous actor (nil actor_id)" do
      event_data = %{
        actor_id: nil,
        actor_type: "anonymous",
        action: "read",
        resource_type: "Invoice",
        resource_id: 111,
        result: "denied",
        reason: "authentication_required"
      }

      job = %Oban.Job{args: event_data, attempt: 1}
      
      assert :ok = AccessEventJob.perform(job)
      
      event = Repo.get_by(AccessEvent, resource_id: 111)
      assert event.actor_id == nil
      assert event.actor_type == "anonymous"
    end

    test "handles IP address and user agent" do
      event_data = %{
        actor_id: 4,
        actor_type: "Fosm.User",
        action: "read",
        resource_type: "Invoice",
        resource_id: 222,
        result: "allowed",
        ip_address: "10.0.0.1",
        user_agent: "Mozilla/5.0"
      }

      job = %Oban.Job{args: event_data, attempt: 1}
      
      assert :ok = AccessEventJob.perform(job)
      
      event = Repo.get_by(AccessEvent, resource_id: 222)
      assert event.ip_address == "10.0.0.1"
      assert event.user_agent == "Mozilla/5.0"
    end
  end

  describe "backoff/1" do
    test "returns exponential backoff" do
      assert AccessEventJob.backoff(%Oban.Job{attempt: 1}) == :timer.seconds(2)
      assert AccessEventJob.backoff(%Oban.Job{attempt: 2}) == :timer.seconds(4)
      assert AccessEventJob.backoff(%Oban.Job{attempt: 3}) == :timer.seconds(8)
    end
  end

  describe "enqueueing" do
    test "can be enqueued with perform_later" do
      event_data = %{
        actor_id: 1,
        actor_type: "Fosm.User",
        action: "read",
        resource_type: "Invoice",
        resource_id: 333,
        result: "allowed"
      }

      assert {:ok, job} = Oban.insert(AccessEventJob.new(event_data))
      assert job.queue == "fosm_logs"
      assert job.max_attempts == 3
    end
  end
end
