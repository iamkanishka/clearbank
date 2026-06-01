defmodule ClearBank.Webhook do
  @moduledoc """
  Webhook envelope struct and parsing.

  Every ClearBank webhook payload has the following shape:

      %{
        "Type" => "TransactionSettled",
        "Version" => 1,
        "Payload" => %{ ... },
        "Nonce" => 123456789
      }

  The `DigitalSignature` and `Nonce` are in the HTTP headers/body.

  ## Signature verification

  Before processing any webhook, always verify the `DigitalSignature` header
  using ClearBank's public key. See `ClearBank.Webhook.Verifier`.

  ## Webhook delivery guarantees

  ClearBank provides **at-least-once** delivery. Your handler must be
  **idempotent**. Detect duplicates by comparing `type`, `timestamp`,
  and `id` in the payload. Respond within **5 seconds** with a `200`
  containing `{"nonce": <value>}` and a valid `DigitalSignature`.
  """

  @type t :: %__MODULE__{
          type: String.t(),
          version: non_neg_integer(),
          payload: map(),
          nonce: integer()
        }

  defstruct [:type, :version, :payload, :nonce]

  @doc """
  Parses a raw webhook body map into a `%ClearBank.Webhook{}` struct.

  ## Examples

      raw = Jason.decode!(conn.body)
      {:ok, webhook} = ClearBank.Webhook.parse(raw)
  """
  @spec parse(map()) :: {:ok, t()} | {:error, :invalid_webhook}
  def parse(%{"Type" => type, "Version" => version, "Payload" => payload, "Nonce" => nonce}) do
    {:ok,
     %__MODULE__{
       type: type,
       version: version,
       payload: payload,
       nonce: nonce
     }}
  end

  def parse(_), do: {:error, :invalid_webhook}

  @doc """
  Builds the JSON response body for a webhook acknowledgement.

  Returns a map `%{"nonce" => nonce}` ready to be JSON-encoded and
  returned in your HTTP response.

  ## Examples

      response_body = ClearBank.Webhook.ack_body(webhook)
      # => %{"nonce" => 123456789}
  """
  @spec ack_body(t()) :: map()
  def ack_body(%__MODULE__{nonce: nonce}), do: %{"nonce" => nonce}
end

defmodule ClearBank.Webhook.Verifier do
  @moduledoc """
  Verifies the `DigitalSignature` on inbound ClearBank webhooks.

  ClearBank signs webhook bodies with their private key. You must verify
  this signature using ClearBank's public key, downloaded from the Portal
  under **Webhook Management > Download Public Key**.

  ## Usage

      # At startup, load ClearBank's public key
      pub_key_pem = File.read!("clearbank_webhook_public_key.pem")

      # In your webhook endpoint handler
      raw_body = conn.assigns[:raw_body]  # capture before any parsing
      signature = Plug.Conn.get_req_header(conn, "digitalsignature") |> List.first()

      case ClearBank.Webhook.Verifier.verify(raw_body, signature, pub_key_pem) do
        :ok ->
          # Signature valid — proceed to parse and process
          {:ok, webhook} = ClearBank.Webhook.parse(Jason.decode!(raw_body))
          process(webhook)

        {:error, :invalid_signature} ->
          # Reject — do not process
          conn |> send_resp(401, "") |> halt()
      end
  """

  alias ClearBank.Auth.Signer

  @doc """
  Verifies a webhook's `DigitalSignature` header.

  Returns `:ok` or `{:error, :invalid_signature | :bad_encoding}`.
  """
  @spec verify(body :: iodata(), signature_b64 :: String.t(), public_key_pem :: binary()) ::
          :ok | {:error, :invalid_signature | :bad_encoding}
  defdelegate verify(body, signature_b64, public_key_pem), to: Signer
end

defmodule ClearBank.Webhook.Handler do
  @moduledoc """
  Behaviour for implementing typed ClearBank webhook handlers.

  ## Usage

  Implement this behaviour in your application to handle specific webhook types:

      defmodule MyApp.ClearBankWebhookHandler do
        use ClearBank.Webhook.Handler

        @impl true
        def handle(%ClearBank.Webhook{type: "TransactionSettled"} = webhook) do
          payload = webhook.payload
          # update your ledger, notify customer, etc.
          :ok
        end

        def handle(%ClearBank.Webhook{type: "FITestEvent"}) do
          :ok
        end

        def handle(webhook) do
          Logger.warning("Unhandled ClearBank webhook: \#{webhook.type}")
          :ok
        end
      end

  ## Plug integration

  Use with a Plug-based router in your Phoenix/Plug app.
  **Critical:** capture the raw body before parsing JSON, so you can verify the signature.

      # In your Router:
      post "/webhooks/clearbank" do
        {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
        signature = List.first(get_req_header(conn, "digitalsignature"))

        with :ok <- ClearBank.Webhook.Verifier.verify(raw_body, signature, pub_key_pem()),
             {:ok, body_map} <- Jason.decode(raw_body),
             {:ok, webhook} <- ClearBank.Webhook.parse(body_map),
             :ok <- MyApp.ClearBankWebhookHandler.handle(webhook) do

          ack_body = Jason.encode!(ClearBank.Webhook.ack_body(webhook))
          sig = ClearBank.Auth.Signer.sign!(ack_body, my_private_key())

          conn
          |> put_resp_header("digitalsignature", sig)
          |> put_resp_content_type("application/json")
          |> send_resp(200, ack_body)
        else
          {:error, :invalid_signature} -> send_resp(conn, 401, "")
          _ -> send_resp(conn, 500, "")
        end
      end

  ## Idempotency

  ClearBank guarantees at-least-once delivery. Always check for duplicate
  webhooks before side-effectful processing. Compare `type` + `id` from
  the payload to detect duplicates.

  ## Response timing

  Respond within **5 seconds**. For slow processing, queue the event and
  respond immediately, then process asynchronously.
  """

  alias ClearBank.Webhook

  @doc """
  Handles an inbound webhook. Return `:ok` on success, `{:error, reason}` on failure.
  """
  @callback handle(Webhook.t()) :: :ok | {:error, term()}

  defmacro __using__(_opts) do
    quote do
      @behaviour ClearBank.Webhook.Handler
      require Logger

      @doc """
      Dispatches a webhook to `handle/1`, logging on error.
      """
      @spec dispatch(ClearBank.Webhook.t()) :: :ok
      def dispatch(%ClearBank.Webhook{} = webhook) do
        case handle(webhook) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.error(
              "[ClearBank] Webhook handler error for #{webhook.type}: #{inspect(reason)}"
            )

            :ok
        end
      end
    end
  end
end
