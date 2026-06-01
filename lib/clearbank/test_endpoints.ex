defmodule ClearBank.TestEndpoints do
  @moduledoc """
  ClearBank API test endpoints for validating authentication and digital signatures.

  Use these endpoints during integration development to verify your:
  - API token (authentication)
  - Digital signature computation (request signing)
  - Webhook subscription (`FITestEvent`)

  These endpoints are available in **both simulation and production**.

  ## Examples

      client = ClearBank.default_client()

      # Test auth only (GET — no DigitalSignature required)
      {:ok, _} = ClearBank.TestEndpoints.ping(client)

      # Test auth + DigitalSignature + trigger FITestEvent webhook
      {:ok, %{"Message" => "hello!"}} = ClearBank.TestEndpoints.echo(client, "hello!")
  """

  alias ClearBank.{Client, HTTP}

  @doc """
  `GET /v1/Test` — verifies your API token (authentication only).

  No `DigitalSignature` header required. Returns `200 OK` on success.

  ## Status codes

  | Code | Meaning |
  |------|---------|
  | 200  | Authentication successful |
  | 403  | Forbidden — invalid or expired API token |
  | 500  | Internal server error |
  | 503  | Service unavailable |

  ## Examples

      {:ok, _} = ClearBank.TestEndpoints.ping(client)
  """
  @spec ping(Client.t()) :: HTTP.result()
  def ping(%Client{} = client) do
    HTTP.get(client, "/v1/Test")
  end

  @doc """
  `POST /v1/Test` — verifies authentication **and** digital signature.

  Echoes back the `body` string in the response as `%{"Message" => body}`.
  If you are subscribed to the `FITestEvent` webhook, this also triggers
  a test webhook delivery to your configured endpoint.

  ## Params

    * `body` - any string to echo back (default: `"ping"`)

  ## Status codes

  | Code | Meaning |
  |------|---------|
  | 200  | Auth + signature valid, body echoed |
  | 403  | Forbidden |
  | 409  | Duplicate `X-Request-Id` |
  | 500  | Internal server error |
  | 503  | Service unavailable |

  ## Examples

      {:ok, %{"Message" => "hello world!"}} =
        ClearBank.TestEndpoints.echo(client, "hello world!")
  """
  @spec echo(Client.t(), String.t()) :: HTTP.result()
  def echo(%Client{} = client, body \\ "ping") when is_binary(body) do
    HTTP.post(client, "/v1/Test", %{"body" => body})
  end
end
