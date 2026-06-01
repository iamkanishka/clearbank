defmodule ClearBank do
  @moduledoc """
  ClearBank UK API client for Elixir.

  ## Overview

  `clearbank` is a production-grade Elixir client covering all ClearBank UK API surfaces:

  - **GBP Accounts** – real and virtual account management, transaction data, Bacs payment data, camt.053 reporting
  - **GBP Payments** – Faster Payments, CHAPS, Bacs, Bacs DDIs, Cheques, GBP Cross-Border, Confirmation of Payee
  - **Multi-currency & FX** – multi-currency account management, high-value international payments, SEPA Credit Transfer UK, FX spot & RFQ
  - **Embedded Banking** – retail/sole-trader/legal-entity customers, hub/payment/savings accounts, Flexible Cash ISAs, interest configuration, KYC
  - **Webhooks** – signature verification, idiomatic handler behaviour

  ## Configuration

  Add to your `config/config.exs` (or `config/runtime.exs` for secrets):

      config :clearbank,
        api_token: System.get_env("CLEARBANK_API_TOKEN"),
        private_key_path: System.get_env("CLEARBANK_PRIVATE_KEY_PATH"),
        environment: :simulation,   # :simulation | :production
        timeout: 30_000,
        pool_size: 10,
        telemetry_prefix: [:clearbank]

  Or pass a client struct per-call for multi-tenant usage:

      client = ClearBank.new(
        api_token: "tok_...",
        private_key: pem_binary,
        environment: :production
      )

      ClearBank.Accounts.list(client)

  ## Error handling

  All functions return `{:ok, response}` or `{:error, %ClearBank.Error{}}`.

      case ClearBank.Payments.FasterPayments.send(client, payment) do
        {:ok, %{status: :accepted}} -> :ok
        {:error, %ClearBank.Error{status: 409}} -> handle_duplicate()
        {:error, %ClearBank.Error{status: 429}} -> handle_rate_limit()
        {:error, err} -> Logger.error(inspect(err))
      end

  ## Telemetry

  The library emits telemetry events under `[:clearbank, :request, :start | :stop | :exception]`.
  See `ClearBank.Telemetry` for full event documentation.
  """

  alias ClearBank.{Client, Config}

  @doc """
  Creates a new client struct for per-request or per-tenant usage.

  ## Options

    * `:api_token` - (required) ClearBank API bearer token
    * `:private_key` - RSA private key as PEM binary (required for mutation requests)
    * `:private_key_path` - Path to PEM file (alternative to `:private_key`)
    * `:environment` - `:simulation` (default) or `:production`
    * `:timeout` - HTTP timeout in ms (default: `30_000`)
    * `:base_url` - Override base URL (useful for tests)

  ## Examples

      client = ClearBank.new(api_token: "tok_xxx", environment: :production)

  """
  @spec new(keyword()) :: Client.t()
  def new(opts \\ []) do
    Client.new(opts)
  end

  @doc """
  Returns the default client built from application config.
  """
  @spec default_client() :: Client.t()
  def default_client do
    Config.default_client()
  end
end
