# ClearBank.ex

[![CI](https://github.com/your-org/clearbank/actions/workflows/ci.yml/badge.svg)](https://github.com/your-org/clearbank/actions)
[![Hex.pm](https://img.shields.io/hexpm/v/clearbank.svg)](https://hex.pm/packages/clearbank)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/clearbank)
[![Coverage](https://codecov.io/gh/your-org/clearbank/branch/main/graph/badge.svg)](https://codecov.io/gh/your-org/clearbank)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A **production-grade Elixir hex package** for the [ClearBank UK API](https://clearbank.github.io/uk).

## Features

- ✅ **Complete API coverage** — GBP Accounts, GBP Payments, Multi-currency & FX, Embedded Banking
- ✅ **RSA-SHA256 digital signatures** — PKCS#1 v1.5, HSM-compatible
- ✅ **Webhook verification & dispatch** — signature verification, idiomatic `Handler` behaviour
- ✅ **Multi-tenant** — per-call client structs for multiple credential sets
- ✅ **NimbleOptions config validation** — fail-fast with clear error messages
- ✅ **Telemetry** — all requests emit structured events
- ✅ **Client-side rate limiter** — token-bucket GenServer
- ✅ **Typed errors** — `%ClearBank.Error{}` with `retryable?/1`
- ✅ **Full test suite** — ExUnit + Bypass HTTP mocking
- ✅ **CI matrix** — Elixir 1.14–1.16, OTP 25–26
- ✅ **Dialyzer + Credo** — strict type checking and linting
- ✅ **ExDoc** with grouped module navigation and guides

---

## Supported APIs

| Area                | Modules                                                                                                                                                              |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GBP Accounts        | `Accounts`, `Accounts.Transactions`, `Accounts.BacsPaymentData`, `Accounts.Reporting`                                                                                |
| GBP Payments        | `Payments.FasterPayments`, `Payments.Chaps`, `Payments.Bacs`, `Payments.BacsDirectDebit`, `Payments.Cheques`, `Payments.CrossBorder`, `Payments.ConfirmationOfPayee` |
| Multi-currency & FX | `MultiCurrency.Accounts`, `MultiCurrency.Payments`, `MultiCurrency.FxTrade`, `MultiCurrency.FxTradeRfq`, `MultiCurrency.SepaCreditTransfer`                          |
| Embedded Banking    | `EmbeddedBanking.Customers`, `EmbeddedBanking.Accounts`, `EmbeddedBanking.Isa`, `EmbeddedBanking.Interest`, `EmbeddedBanking.Kyc`                                    |
| Webhooks            | `Webhook`, `Webhook.Verifier`, `Webhook.Handler`                                                                                                                     |

---

## Installation

```elixir
# mix.exs
def deps do
  [
    {:clearbank, "~> 1.0"}
  ]
end
```

---

## Quick Start

### 1. Configure

```elixir
# config/runtime.exs
config :clearbank,
  api_token: System.fetch_env!("CLEARBANK_API_TOKEN"),
  private_key_path: System.fetch_env!("CLEARBANK_PRIVATE_KEY_PATH"),
  environment: :simulation  # :simulation | :production
```

### 2. Use

```elixir
client = ClearBank.default_client()

# List GBP accounts
{:ok, %{"accounts" => accounts}} = ClearBank.Accounts.list(client)

# Send a Faster Payment
{:ok, _} = ClearBank.Payments.FasterPayments.send(client, %{
  account_id: "your-account-uuid",
  amount: "100.00",
  currency: "GBP",
  destination_sort_code: "040004",
  destination_account_number: "12345678",
  destination_account_name: "Jane Smith",
  reference: "Invoice 001"
})

# Execute an FX spot trade
{:ok, trade} = ClearBank.MultiCurrency.FxTrade.execute(client, %{
  sell_account_id: "eur-account-uuid",
  buy_account_id: "gbp-account-uuid",
  sell_currency: "EUR",
  buy_currency: "GBP",
  sell_amount: "10000.00"
})

# Create an embedded retail customer
{:ok, customer} = ClearBank.EmbeddedBanking.Customers.create_retail(client, %{
  first_name: "Alice",
  last_name: "Smith",
  date_of_birth: "1990-05-15",
  email: "alice@example.com"
})
```

### 3. Handle Webhooks

```elixir
defmodule MyApp.WebhookHandler do
  use ClearBank.Webhook.Handler

  @impl true
  def handle(%ClearBank.Webhook{type: "TransactionSettled", payload: payload}) do
    MyApp.Ledger.record(payload)
    :ok
  end

  def handle(_webhook), do: :ok
end
```

### 4. Error Handling

```elixir
case ClearBank.Payments.FasterPayments.send(client, payment) do
  {:ok, _}                                    -> :ok
  {:error, %ClearBank.Error{status: 409}}     -> :duplicate_ignored
  {:error, %ClearBank.Error{status: 429}}     -> retry_later()
  {:error, err} when ClearBank.Error.retryable?(err) -> retry_with_same_id()
  {:error, err}                               -> Logger.error(inspect(err))
end
```

---

## Development

```bash
mix deps.get
mix test
mix test --cover
mix credo --strict
mix dialyzer
mix docs
```

---

## Security

- Never commit your `private_key.pem` — add it to `.gitignore`
- In production, load private keys from an HSM, not the filesystem
- Rotate API tokens before their 1-year expiry
- Verify all inbound webhook signatures before processing
- Store `X-Correlation-Id` from error responses — required for ClearBank support

---

## License

MIT — see [LICENSE](LICENSE).

---

## Contributing

Pull requests welcome. Please ensure `mix test`, `mix credo --strict`,
and `mix dialyzer` all pass before submitting.
