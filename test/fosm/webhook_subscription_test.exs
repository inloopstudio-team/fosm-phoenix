defmodule Fosm.WebhookSubscriptionTest do
  @moduledoc """
  Tests for the WebhookSubscription schema.
  """
  use ExUnit.Case, async: true
  alias Fosm.WebhookSubscription

  describe "changeset/2" do
    test "validates required fields" do
      changeset = WebhookSubscription.changeset(%WebhookSubscription{}, %{})
      
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).url
    end

    test "valid changeset with only url" do
      attrs = %{url: "https://example.com/webhook"}
      
      changeset = WebhookSubscription.changeset(%WebhookSubscription{}, attrs)
      assert changeset.valid?
    end

    test "validates url format" do
      attrs = %{url: "not-a-valid-url"}
      
      changeset = WebhookSubscription.changeset(%WebhookSubscription{}, attrs)
      assert changeset.valid? == false
      assert "must be a valid URL" in errors_on(changeset).url
    end

    test "validates url format for http urls" do
      attrs = %{url: "http://example.com/webhook"}
      
      changeset = WebhookSubscription.changeset(%WebhookSubscription{}, attrs)
      assert changeset.valid?
    end

    test "validates url format for https urls" do
      attrs = %{url: "https://example.com/webhook"}
      
      changeset = WebhookSubscription.changeset(%WebhookSubscription{}, attrs)
      assert changeset.valid?
    end

    test "validates delivery_mode inclusion" do
      attrs = %{
        url: "https://example.com/webhook",
        delivery_mode: "invalid"
      }
      
      changeset = WebhookSubscription.changeset(%WebhookSubscription{}, attrs)
      assert changeset.valid? == false
      assert "is invalid" in errors_on(changeset).delivery_mode
    end

    test "accepts valid delivery modes" do
      for mode <- ["sync", "async"] do
        attrs = %{
          url: "https://example.com/webhook",
          delivery_mode: mode
        }
        
        changeset = WebhookSubscription.changeset(%WebhookSubscription{}, attrs)
        assert changeset.valid?, "Expected #{mode} to be valid"
      end
    end

    test "accepts optional fields" do
      attrs = %{
        url: "https://example.com/webhook",
        events: ["pay", "cancel"],
        record_type: "Fosm.Invoice",
        record_id: "123",
        secret_token: "secret123",
        active: true,
        delivery_mode: "async",
        retry_count: 3,
        last_delivery_at: DateTime.utc_now(),
        last_delivery_status: "success",
        metadata: %{"custom" => "data"}
      }
      
      changeset = WebhookSubscription.changeset(%WebhookSubscription{}, attrs)
      assert changeset.valid?
      
      assert get_change(changeset, :url) == "https://example.com/webhook"
      assert get_change(changeset, :events) == ["pay", "cancel"]
      assert get_change(changeset, :secret_token) == "secret123"
    end

    test "validates empty events array means subscribe to all" do
      attrs = %{
        url: "https://example.com/webhook",
        events: []
      }
      
      changeset = WebhookSubscription.changeset(%WebhookSubscription{}, attrs)
      assert changeset.valid?
    end

    test "validates nil events means subscribe to all" do
      attrs = %{
        url: "https://example.com/webhook",
        events: nil
      }
      
      changeset = WebhookSubscription.changeset(%WebhookSubscription{}, attrs)
      assert changeset.valid?
    end
  end

  describe "query scopes" do
    test "active/1 filters active subscriptions" do
      query = WebhookSubscription.active()
      
      assert inspect(query) =~ "active == true"
    end

    test "for_event/2 filters by event" do
      query = WebhookSubscription.for_event("pay")
      
      assert inspect(query) =~ "pay"
    end

    test "for_record_type/2 filters by record type" do
      query = WebhookSubscription.for_record_type("Fosm.Invoice")
      
      assert inspect(query) =~ "record_type == \"Fosm.Invoice\""
    end

    test "for_record/3 filters by record type and id" do
      query = WebhookSubscription.for_record("Fosm.Invoice", 123)
      
      assert inspect(query) =~ "record_type == \"Fosm.Invoice\""
      assert inspect(query) =~ "record_id == \"123\""
    end

    test "system_wide/1 filters system-wide subscriptions" do
      query = WebhookSubscription.system_wide()
      
      assert inspect(query) =~ "is_nil(record_type)"
    end

    test "per_type/1 filters per-type subscriptions" do
      query = WebhookSubscription.per_type()
      
      assert inspect(query) =~ "not is_nil(record_type)"
      assert inspect(query) =~ "is_nil(record_id)"
    end

    test "per_record/1 filters per-record subscriptions" do
      query = WebhookSubscription.per_record()
      
      assert inspect(query) =~ "not is_nil(record_id)"
    end

    test "needs_retry/2 filters subscriptions needing retry" do
      query = WebhookSubscription.needs_retry(10)
      
      assert inspect(query) =~ "retry_count < 10"
      assert inspect(query) =~ "not is_nil(last_delivery_status)"
    end
  end

  describe "signature functions" do
    test "generate_signature/2 creates HMAC SHA256 signature" do
      payload = %{"event" => "pay", "record_id" => "123"}
      secret = "mysecret"
      
      signature = WebhookSubscription.generate_signature(payload, secret)
      
      assert is_binary(signature)
      assert String.length(signature) == 64  # SHA256 hex = 64 chars
      assert Regex.match?(~r/^[a-f0-9]+$/, signature)
    end

    test "generate_signature/2 is consistent for same input" do
      payload = %{"event" => "pay"}
      secret = "mysecret"
      
      sig1 = WebhookSubscription.generate_signature(payload, secret)
      sig2 = WebhookSubscription.generate_signature(payload, secret)
      
      assert sig1 == sig2
    end

    test "generate_signature/2 differs for different secrets" do
      payload = %{"event" => "pay"}
      
      sig1 = WebhookSubscription.generate_signature(payload, "secret1")
      sig2 = WebhookSubscription.generate_signature(payload, "secret2")
      
      assert sig1 != sig2
    end

    test "verify_signature?/3 returns true for valid signature" do
      payload = %{"event" => "pay"}
      secret = "mysecret"
      signature = WebhookSubscription.generate_signature(payload, secret)
      
      assert WebhookSubscription.verify_signature?(payload, secret, signature)
    end

    test "verify_signature?/3 returns false for invalid signature" do
      payload = %{"event" => "pay"}
      secret = "mysecret"
      
      refute WebhookSubscription.verify_signature?(payload, secret, "invalid")
    end

    test "verify_signature?/3 returns false for tampered payload" do
      payload = %{"event" => "pay"}
      tampered_payload = %{"event" => "cancel"}
      secret = "mysecret"
      signature = WebhookSubscription.generate_signature(payload, secret)
      
      refute WebhookSubscription.verify_signature?(tampered_payload, secret, signature)
    end
  end

  # Helper functions
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{\w+}", message, fn _, key ->
        opts |> Keyword.get(String.to_atom(key), key) |> to_string()
      end)
    end)
  end

  defp get_change(changeset, field) do
    Ecto.Changeset.get_change(changeset, field)
  end
end
