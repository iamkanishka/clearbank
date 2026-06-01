defmodule ClearBank.WebhookTest do
  use ExUnit.Case, async: true

  alias ClearBank.Auth.Signer
  alias ClearBank.TestSupport
  alias ClearBank.Webhook
  alias ClearBank.Webhook.Verifier

  describe "parse/1" do
    test "parses a valid webhook map" do
      raw = TestSupport.webhook_fixture()
      assert {:ok, %Webhook{} = wh} = Webhook.parse(raw)
      assert wh.type == "TransactionSettled"
      assert wh.version == 1
      assert wh.nonce == 123_456_789
      assert wh.payload["transactionId"] == "txn-uuid-1"
    end

    test "returns error for invalid shape" do
      assert {:error, :invalid_webhook} = Webhook.parse(%{"foo" => "bar"})
    end

    test "returns error for non-map" do
      assert {:error, :invalid_webhook} = Webhook.parse("not a map")
    end
  end

  describe "ack_body/1" do
    test "returns map with nonce" do
      {:ok, wh} = Webhook.parse(TestSupport.webhook_fixture())
      assert Webhook.ack_body(wh) == %{"nonce" => 123_456_789}
    end
  end

  describe "Verifier.verify/3" do
    test "verifies a correctly signed webhook" do
      {priv, pub} = TestSupport.generate_key_pair()
      body = ~s({"nonce": 99})
      {:ok, sig} = Signer.sign(body, priv)

      assert :ok = Verifier.verify(body, sig, pub)
    end

    test "rejects tampered body" do
      {priv, pub} = TestSupport.generate_key_pair()
      {:ok, sig} = Signer.sign("real body", priv)

      assert {:error, :invalid_signature} = Verifier.verify("tampered", sig, pub)
    end
  end
end

defmodule ClearBank.Webhook.HandlerTest do
  use ExUnit.Case, async: true

  alias ClearBank.TestSupport
  alias ClearBank.Webhook

  defmodule TestHandler do
    use ClearBank.Webhook.Handler

    def handle(%Webhook{type: "TransactionSettled"} = _wh), do: :ok
    def handle(%Webhook{type: "FITestEvent"}), do: :ok
    def handle(%Webhook{type: "ShouldFail"}), do: {:error, :processing_failed}
    def handle(_), do: :ok
  end

  test "dispatches known events successfully" do
    {:ok, wh} = Webhook.parse(TestSupport.webhook_fixture(%{"Type" => "TransactionSettled"}))
    assert :ok = TestHandler.dispatch(wh)
  end

  test "dispatches FITestEvent" do
    {:ok, wh} = Webhook.parse(TestSupport.webhook_fixture(%{"Type" => "FITestEvent"}))
    assert :ok = TestHandler.dispatch(wh)
  end

  test "logs error but still returns :ok on handler failure" do
    {:ok, wh} = Webhook.parse(TestSupport.webhook_fixture(%{"Type" => "ShouldFail"}))
    assert :ok = TestHandler.dispatch(wh)
  end

  test "handles unknown event types" do
    {:ok, wh} = Webhook.parse(TestSupport.webhook_fixture(%{"Type" => "UnknownEvent"}))
    assert :ok = TestHandler.dispatch(wh)
  end
end
