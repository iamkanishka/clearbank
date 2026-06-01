defmodule ClearBank.HTTP do
  @moduledoc """
  Core HTTP request pipeline for the ClearBank API.

  Handles:
  - Authorization header injection
  - DigitalSignature computation for mutating requests
  - X-Request-Id generation (UUID v4) with optional override for retry safety
  - X-Correlation-Id capture from responses
  - Retry-After header parsing on 503
  - Telemetry events
  - Unified error mapping to `ClearBank.Error`

  ## Retry safety

  ClearBank requires retrying 5XX errors with the **exact same `X-Request-Id`**.
  Pass `:request_id` in opts to pin the ID across retry attempts:

      stable_id = ClearBank.HTTP.generate_request_id()

      ClearBank.HTTP.Retry.with_retry(fn ->
        ClearBank.HTTP.post(client, "/v3/Payments/FPS", body, request_id: stable_id)
      end)
  """

  alias ClearBank.{Auth.Signer, Client, Error, Telemetry}
  require Logger

  import Bitwise, only: [band: 2, bor: 2]

  @mutating_methods [:post, :put, :patch]

  @type method :: :get | :post | :put | :patch | :delete
  @type path :: String.t()
  @type opts :: keyword()
  @type result :: {:ok, map() | list() | nil} | {:error, Error.t()}

  @doc """
  Performs a GET request.

  ## Options

    * `:request_id` - override the auto-generated X-Request-Id (for retry with same ID)
  """
  @spec get(Client.t(), path(), opts()) :: result()
  def get(%Client{} = client, path, opts \\ []) do
    request(client, :get, path, opts)
  end

  @doc """
  Performs a POST request.

  ## Options

    * `:request_id` - pin X-Request-Id for idempotent retries
  """
  @spec post(Client.t(), path(), body :: map(), opts()) :: result()
  def post(%Client{} = client, path, body \\ %{}, opts \\ []) do
    request(client, :post, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Performs a PUT request.
  """
  @spec put(Client.t(), path(), body :: map(), opts()) :: result()
  def put(%Client{} = client, path, body \\ %{}, opts \\ []) do
    request(client, :put, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Performs a PATCH request.
  """
  @spec patch(Client.t(), path(), body :: map(), opts()) :: result()
  def patch(%Client{} = client, path, body \\ %{}, opts \\ []) do
    request(client, :patch, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Performs a DELETE request.
  """
  @spec delete(Client.t(), path(), opts()) :: result()
  def delete(%Client{} = client, path, opts \\ []) do
    request(client, :delete, path, opts)
  end

  @doc """
  Generates a UUID v4 string suitable for use as `X-Request-Id`.

  Pre-generate a stable ID when you need to retry a request with the same ID —
  ClearBank's idempotency requirement for 5XX retries.

  ## Examples

      id = ClearBank.HTTP.generate_request_id()
      # => "550e8400-e29b-4d3f-a716-446655440000"

      ClearBank.HTTP.Retry.with_retry(fn ->
        ClearBank.HTTP.post(client, "/v3/Payments/FPS", body, request_id: id)
      end)
  """
  @spec generate_request_id() :: String.t()
  def generate_request_id do
    # Extract 5 independent integer fields from 16 random bytes.
    # Apply version (4) and variant (10xx) bits using band/bor on the
    # individual 16-bit integers — Dialyzer can prove these are integers,
    # avoiding false boolean warnings from shift operators.
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)

    # Version 4: top nibble of c = 0100
    c4 = bor(band(c, 0x0FFF), 0x4000)

    # Variant 1: top two bits of d = 10
    dv = bor(band(d, 0x3FFF), 0x8000)

    :io_lib.format(
      "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b",
      [a, b, c4, dv, e]
    )
    |> IO.iodata_to_binary()
  end

  # --- Private ---

  defp request(%Client{} = client, method, path, opts) do
    request_id = Keyword.get(opts, :request_id) || generate_request_id()
    url = client.base_url <> path
    body_map = Keyword.get(opts, :json)
    {body_json, body_bin} = encode_body(body_map)
    headers = build_headers(client, method, body_bin, request_id)

    req_opts =
      [method: method, url: url, headers: headers, receive_timeout: client.timeout]
      |> maybe_put_body(body_json)
      |> Keyword.merge(Keyword.drop(opts, [:json, :request_id]))

    metadata = %{method: method, url: url, request_id: request_id}
    start_time = Telemetry.start(client.telemetry_prefix, metadata)

    result =
      try do
        req_opts
        |> Req.new()
        |> Req.request()
        |> handle_response(request_id)
      rescue
        e ->
          Logger.error("[ClearBank] Request exception: #{inspect(e)}")
          {:error, Error.from_exception(e)}
      end

    Telemetry.stop(client.telemetry_prefix, start_time, metadata, result)
    result
  end

  defp encode_body(nil), do: {nil, ""}

  defp encode_body(body) do
    json = Jason.encode!(body)
    {json, json}
  end

  defp build_headers(client, method, body_bin, request_id) do
    base = [
      {"Authorization", "Bearer #{client.api_token}"},
      {"X-Request-Id", request_id},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    if (method in @mutating_methods and client.private_key) && body_bin != "" do
      sig = Signer.sign!(body_bin, client.private_key)
      [{"DigitalSignature", sig} | base]
    else
      base
    end
  end

  defp maybe_put_body(opts, nil), do: opts
  defp maybe_put_body(opts, body_json), do: Keyword.put(opts, :body, body_json)

  defp handle_response({:ok, %Req.Response{status: status} = resp}, _request_id)
       when status in 200..299 do
    {:ok, parse_body(resp.body)}
  end

  defp handle_response({:ok, %Req.Response{status: 503} = resp}, request_id) do
    error = Error.from_response(resp, request_id)
    # Req.Response.headers is a map() — use Map.get, not List.keyfind.
    # The header key is already lowercased by Req/Mint.
    retry_after = parse_retry_after_header(Map.get(resp.headers, "retry-after"))

    if retry_after do
      Logger.warning(
        "[ClearBank] 503 Service Unavailable. " <>
          "Retry-After: #{retry_after}s. " <>
          "X-Correlation-Id: #{inspect(error.correlation_id)}"
      )
    end

    updated_details = Map.put(error.details || %{}, "retry_after_seconds", retry_after)
    {:error, %{error | details: updated_details}}
  end

  defp handle_response({:ok, %Req.Response{} = resp}, request_id) do
    {:error, Error.from_response(resp, request_id)}
  end

  defp handle_response({:error, %{reason: reason}}, _request_id) do
    {:error, Error.from_exception(reason)}
  end

  defp handle_response({:error, reason}, _request_id) do
    {:error, Error.from_exception(reason)}
  end

  defp parse_body(""), do: nil
  defp parse_body(nil), do: nil
  defp parse_body(body) when is_map(body) or is_list(body), do: body

  defp parse_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> parsed
      {:error, _} -> body
    end
  end

  # Parse a Retry-After header value string into an integer number of seconds.
  # Called with the result of Map.get(resp.headers, "retry-after") which is
  # either a binary or nil — both cases are handled explicitly.
  defp parse_retry_after_header(nil), do: nil

  defp parse_retry_after_header(value) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, _rest} -> seconds
      :error -> nil
    end
  end
end
