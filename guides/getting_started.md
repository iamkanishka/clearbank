# Getting Started

This guide walks you through integrating `clearbank` into your Elixir application
from configuration through your first live API call.

## Prerequisites

- You have been onboarded by ClearBank as a customer
- You have a **ClearBank Portal** account with access to **Institution > Certificates and Tokens**
- You have an RSA key pair (see below)

---

## Installation

Add `clearbank` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:clearbank, "~> 0.1"}
  ]
end
```

Then fetch:

```bash
mix deps.get
```

---

## Step 1: Generate Your Key Pair

In **simulation**, you can use any RSA 2048-bit key pair.
In **production**, your private key must be stored in a FIPS 140-2 level 2 compliant HSM
(e.g. Azure Key Vault HSM, AWS CloudHSM, Google Cloud HSM).

```bash
# Generate private key (PKCS#8 format)
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out private_key.pem

# Extract public key
openssl rsa -pubout -in private_key.pem -out public_key.pem

# Generate CSR (upload this to ClearBank Portal)
openssl req -new -key private_key.pem -out clearbank.csr
```

---

## Step 2: Upload CSR and Get Your API Token

1. Log in to the ClearBank Portal
2. Go to **Institution > Certificates and Tokens**
3. Click **Generate API Token**
4. Upload your `.csr` file
5. Set a name and expiry (maximum 1 year)
6. **Copy the token immediately** — it is shown only once

---

## Step 3: Configure the Library

In `config/runtime.exs` (recommended for secrets):

```elixir
config :clearbank,
  api_token: System.fetch_env!("CLEARBANK_API_TOKEN"),
  private_key_path: System.fetch_env!("CLEARBANK_PRIVATE_KEY_PATH"),
  environment: :simulation,  # :simulation | :production
  timeout: 30_000
```

In your `.env` or secrets manager:

```bash
CLEARBANK_API_TOKEN=your_token_here
CLEARBANK_PRIVATE_KEY_PATH=/secure/path/to/private_key.pem
```

---

## Step 4: Test Your Connection

```elixir
client = ClearBank.default_client()

# Test authentication (GET — no signature required)
{:ok, _} = ClearBank.HTTP.get(client, "/v1/Test")

# Test authentication + signature (POST)
{:ok, %{"Message" => msg}} = ClearBank.HTTP.post(client, "/v1/Test", %{body: "hello"})
IO.puts(msg)  # => "hello"
```

---

## Step 5: Make Your First Real API Call

```elixir
client = ClearBank.default_client()

# List your GBP accounts
{:ok, response} = ClearBank.Accounts.list(client)
IO.inspect(response["accounts"])

# Send a Faster Payment
{:ok, result} = ClearBank.Payments.FasterPayments.send(client, %{
  account_id: "your-account-uuid",
  amount: "10.00",
  currency: "GBP",
  destination_sort_code: "040004",
  destination_account_number: "12345678",
  destination_account_name: "Jane Smith",
  reference: "Test payment"
})
```

---

## Multi-tenant Usage

If you manage multiple institutions or have multiple credential sets,
pass a client per call rather than using the application default:

```elixir
client_a = ClearBank.new(api_token: token_a, private_key: key_a, environment: :production)
client_b = ClearBank.new(api_token: token_b, private_key: key_b, environment: :production)

ClearBank.Accounts.list(client_a)
ClearBank.Accounts.list(client_b)
```

---

## Handling Webhooks

1. **Download ClearBank's public key** from Portal → **Webhook Management > Download Public Key**
2. Store it securely (e.g. in an env var or secret store)
3. Register your webhook URL in the Portal

Implement a handler in your Phoenix router:

```elixir
# In your Plug/Phoenix router
post "/webhooks/clearbank" do
  {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
  signature = conn |> get_req_header("digitalsignature") |> List.first()
  pub_key_pem = Application.fetch_env!(:my_app, :clearbank_webhook_public_key)

  with :ok <- ClearBank.Webhook.Verifier.verify(raw_body, signature, pub_key_pem),
       {:ok, body_map} <- Jason.decode(raw_body),
       {:ok, webhook} <- ClearBank.Webhook.parse(body_map),
       :ok <- MyApp.WebhookHandler.dispatch(webhook) do

    ack = Jason.encode!(ClearBank.Webhook.ack_body(webhook))
    sig = ClearBank.Auth.Signer.sign!(ack, private_key_pem())

    conn
    |> put_resp_header("digitalsignature", sig)
    |> put_resp_content_type("application/json")
    |> send_resp(200, ack)
  else
    {:error, :invalid_signature} -> send_resp(conn, 401, "")
    _ -> send_resp(conn, 500, "")
  end
end
```

Implement your handler:

```elixir
defmodule MyApp.WebhookHandler do
  use ClearBank.Webhook.Handler

  @impl true
  def handle(%ClearBank.Webhook{type: "TransactionSettled", payload: payload}) do
    # Update your ledger, notify customer, etc.
    MyApp.Ledger.record_settlement(payload)
    :ok
  end

  def handle(%ClearBank.Webhook{type: "FITestEvent"}) do
    :ok
  end

  def handle(webhook) do
    Logger.warning("Unhandled webhook: #{webhook.type}")
    :ok
  end
end
```

> **Critical:** Your handler must be **idempotent**. ClearBank guarantees
> at-least-once delivery. Always respond within **5 seconds** — queue and
> process asynchronously for slow operations.

---

## Error Handling

All functions return `{:ok, result}` or `{:error, %ClearBank.Error{}}`:

```elixir
case ClearBank.Payments.FasterPayments.send(client, payment) do
  {:ok, _} ->
    :ok

  {:error, %ClearBank.Error{status: 409}} ->
    # Duplicate X-Request-Id — idempotent, payment likely already submitted
    :ok

  {:error, %ClearBank.Error{status: 429} = err} ->
    # Rate limited — back off and retry
    Logger.warning("Rate limited. Correlation ID: #{err.correlation_id}")
    {:error, :rate_limited}

  {:error, %ClearBank.Error{status: status} = err} when status in [500, 503] ->
    # Retryable server error — retry with same X-Request-Id
    Logger.error("Retryable error: #{inspect(err)}")
    {:error, :retryable}

  {:error, err} ->
    Logger.error("Unrecoverable error: #{inspect(err)}")
    {:error, err}
end
```

Use `ClearBank.Error.retryable?/1` to programmatically check:

```elixir
case result do
  {:error, err} when ClearBank.Error.retryable?(err) -> retry()
  {:error, err} -> handle_permanent_error(err)
end
```

---

## Telemetry

Attach telemetry handlers to observe all requests:

```elixir
:telemetry.attach_many(
  "clearbank-logger",
  [
    [:clearbank, :request, :start],
    [:clearbank, :request, :stop],
    [:clearbank, :request, :exception]
  ],
  fn event, measurements, metadata, _config ->
    case event do
      [:clearbank, :request, :stop] ->
        duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
        Logger.info("ClearBank #{metadata.method} #{metadata.url} #{duration_ms}ms")

      [:clearbank, :request, :exception] ->
        Logger.error("ClearBank request failed: #{inspect(metadata.error)}")

      _ -> :ok
    end
  end,
  nil
)
```
