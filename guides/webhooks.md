# Webhook Integration Guide

This guide covers everything you need to handle ClearBank webhooks correctly
in a production Elixir application.

## Overview

ClearBank sends webhooks for all asynchronous events — payment settlements,
KYC status changes, DDI changes, FX trades, and more. Webhooks are:

- **Signed** — every request includes a `DigitalSignature` header you must verify
- **At-least-once** — your handlers must be **idempotent**
- **Time-limited** — you must respond with `200` within **5 seconds**
- **Retried** — if ClearBank doesn't receive a valid response, it retries every 15 minutes for 24 hours

## Step 1: Download ClearBank's Public Key

In the ClearBank Portal, go to **Webhook Management > Download Public Key**.
Store it in your application config or secret manager:

```bash
export CLEARBANK_WEBHOOK_PUBLIC_KEY="$(cat clearbank_webhook_public.pem)"
```

```elixir
# config/runtime.exs
config :my_app,
  clearbank_webhook_public_key: System.fetch_env!("CLEARBANK_WEBHOOK_PUBLIC_KEY")
```

## Step 2: Configure Your Webhook URL

In the Portal under **Institution > Webhook Management**:

1. Search for the event type (e.g. `TransactionSettled`)
2. Click **Edit**
3. Enter your HTTPS endpoint URL
4. Set status to **Enabled**

> Never include API keys or tokens in webhook URLs.

**Allowed IP ranges** (add to your firewall allowlist):

| Environment | CIDRs |
|---|---|
| Simulation | `51.145.122.16/28`, `20.39.213.0/28`, `172.187.147.144/28`, `20.117.212.176/28` |
| Production | `51.145.122.32/28`, `172.187.179.192/28`, `172.187.243.32/28`, `20.117.189.64/28` |

## Step 3: Implement the Endpoint

### Phoenix Router

```elixir
# router.ex
scope "/webhooks", MyAppWeb do
  post "/clearbank", WebhookController, :handle
end
```

### Controller

```elixir
defmodule MyAppWeb.WebhookController do
  use MyAppWeb, :controller

  alias ClearBank.{Webhook, Webhook.Verifier, Auth.Signer}

  def handle(conn, _params) do
    with {:ok, raw_body} <- read_raw_body(conn),
         {:ok, signature} <- get_signature(conn),
         :ok <- verify_signature(raw_body, signature),
         {:ok, body_map} <- Jason.decode(raw_body),
         {:ok, webhook} <- Webhook.parse(body_map),
         :ok <- MyApp.WebhookDispatcher.dispatch(webhook) do

      # Build acknowledgement
      ack = Jason.encode!(Webhook.ack_body(webhook))
      private_key = Application.fetch_env!(:my_app, :clearbank_private_key)
      ack_sig = Signer.sign!(ack, private_key)

      conn
      |> put_resp_header("digitalsignature", ack_sig)
      |> put_resp_content_type("application/json")
      |> send_resp(200, ack)

    else
      {:error, :invalid_signature} ->
        send_resp(conn, 401, "")

      {:error, :invalid_webhook} ->
        send_resp(conn, 400, "")

      {:error, _reason} ->
        send_resp(conn, 500, "")
    end
  end

  # IMPORTANT: capture raw body before any plug parses it
  defp read_raw_body(conn) do
    case conn.assigns[:raw_body] do
      nil -> {:error, :no_raw_body}
      body -> {:ok, body}
    end
  end

  defp get_signature(conn) do
    case get_req_header(conn, "digitalsignature") do
      [sig | _] -> {:ok, sig}
      [] -> {:error, :missing_signature}
    end
  end

  defp verify_signature(body, signature) do
    pub_key = Application.fetch_env!(:my_app, :clearbank_webhook_public_key)
    Verifier.verify(body, signature, pub_key)
  end
end
```

### Raw Body Plug

Phoenix parses the body as JSON before your controller sees it.
Add this plug to capture the raw bytes first:

```elixir
defmodule MyApp.RawBodyPlug do
  @moduledoc "Captures raw request body before JSON parsing."

  def init(opts), do: opts

  def call(conn, _opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    Plug.Conn.assign(conn, :raw_body, body)
  end
end
```

In your endpoint:

```elixir
# endpoint.ex
plug MyApp.RawBodyPlug, [path: "/webhooks/clearbank"]

plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  json_decoder: Phoenix.json_library()
```

## Step 4: Implement a Handler

```elixir
defmodule MyApp.WebhookDispatcher do
  use ClearBank.Webhook.Handler

  alias ClearBank.Webhook
  alias ClearBank.Webhook.Events

  require Logger

  @impl true
  def handle(%Webhook{type: "TransactionSettled"} = webhook) do
    event = Events.TransactionSettled.from_payload(webhook.payload)

    # Queue for async processing — respond immediately
    MyApp.PaymentWorker.enqueue(%{
      transaction_id: event.transaction_id,
      account_id: event.account_id,
      amount: event.amount,
      direction: event.direction
    })

    :ok
  end

  def handle(%Webhook{type: "CustomerKycStatusChanged"} = webhook) do
    event = Events.CustomerKycStatusChanged.from_payload(webhook.payload)

    MyApp.KycWorker.enqueue(%{
      customer_id: event.customer_id,
      new_status: event.new_status
    })

    :ok
  end

  def handle(%Webhook{type: "FITestEvent"}) do
    Logger.info("ClearBank test webhook received")
    :ok
  end

  def handle(%Webhook{type: type} = _webhook) do
    Logger.warning("Unhandled ClearBank webhook type: #{type}")
    :ok
  end
end
```

## Step 5: Idempotent Processing

Since ClearBank may deliver the same webhook more than once, always check
before applying side effects:

```elixir
defmodule MyApp.PaymentWorker do
  use Oban.Worker, queue: :clearbank_webhooks

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"transaction_id" => txn_id} = args}) do
    # Idempotent: check if already processed
    if MyApp.Repo.exists?(MyApp.Payment, transaction_id: txn_id) do
      :ok
    else
      MyApp.Ledger.record_settlement(args)
    end
  end
end
```

## All Supported Event Types

| Event Type | Struct | Description |
|---|---|---|
| `FITestEvent` | `Events.FITestEvent` | Triggered by `POST /v1/Test` |
| `TransactionSettled` | `Events.TransactionSettled` | Payment settled (FPS, CHAPS, Bacs, internal) |
| `PaymentMessageAssessmentFailed` | `Events.PaymentMessageAssessmentFailed` | Payment rejected pre-settlement |
| `PaymentMessageValidationFailed` | `Events.PaymentMessageValidationFailed` | Payment failed validation |
| `TransactionRejected` | `Events.TransactionRejected` | Payment rejected post-submission |
| `FpsPaymentReturnCreated` | `Events.FpsPaymentReturnCreated` | FPS return created |
| `BacsPaymentCreated` | `Events.BacsPaymentCreated` | Bacs payment created |
| `BacsMandateCreated` | `Events.BacsMandateCreated` | DDI created |
| `BacsMandateCancelled` | `Events.BacsMandateCancelled` | DDI cancelled |
| `BacsMandateMigrated` | `Events.BacsMandateMigrated` | DDI migrated between SUNs |
| `ChapsPaymentCreated` | `Events.ChapsPaymentCreated` | CHAPS payment accepted |
| `ChapsReturnCreated` | `Events.ChapsReturnCreated` | CHAPS return created |
| `CopOutboundResponse` | `Events.CopOutboundResponse` | CoP name check response |
| `MccyTransactionCreated` | `Events.MccyTransactionCreated` | Multi-currency transaction |
| `FxTradeCreated` | `Events.FxTradeCreated` | FX trade executed |
| `FxTradeSettled` | `Events.FxTradeSettled` | FX trade settled |
| `CustomerKycStatusChanged` | `Events.CustomerKycStatusChanged` | Embedded KYC status change |
| `EmbeddedAccountCreated` | `Events.EmbeddedAccountCreated` | Embedded account created |
| `EmbeddedTransactionSettled` | `Events.EmbeddedTransactionSettled` | Embedded payment settled |

Use `ClearBank.Webhook.Events.parse/2` to get a typed struct from any event:

```elixir
{:ok, event} = ClearBank.Webhook.Events.parse(webhook.type, webhook.payload)
```
