defmodule ClearBank.Error do
  @moduledoc """
  Represents a ClearBank API error.

  ## Fields

    * `:status` - HTTP status code (e.g., `400`, `409`, `429`)
    * `:code` - ClearBank error code string if available
    * `:message` - Human-readable error description
    * `:details` - Raw error map from the API response body
    * `:request_id` - The `X-Request-Id` from the original request
    * `:correlation_id` - The `X-Correlation-Id` returned by ClearBank (store for support)

  ## Common status codes

    * `400` - Bad request (invalid payload, missing required field)
    * `401` - Unauthorised (invalid/expired API token)
    * `403` - Forbidden
    * `404` - Not found
    * `409` - Conflict (duplicate `X-Request-Id`)
    * `422` - Unprocessable entity
    * `429` - Rate limited (back off and retry)
    * `500` - Internal server error (retry with same X-Request-Id)
    * `503` - Service unavailable (check `Retry-After` header and retry)
  """

  @type t :: %__MODULE__{
          status: non_neg_integer() | nil,
          code: String.t() | nil,
          message: String.t(),
          details: map() | nil,
          request_id: String.t() | nil,
          correlation_id: String.t() | nil
        }

  defexception [:status, :code, :message, :details, :request_id, :correlation_id]

  @impl true
  def message(%__MODULE__{status: status, message: msg, correlation_id: corr_id}) do
    base = "ClearBank API error #{status}: #{msg}"
    if corr_id, do: "#{base} (X-Correlation-Id: #{corr_id})", else: base
  end

  @doc """
  Builds a `%ClearBank.Error{}` from a response map (status + headers + body).
  Accepts any struct or map with `:status`, `:headers`, `:body` fields.
  """
  @spec from_response(term(), String.t() | nil) :: t()
  def from_response(resp, request_id \\ nil) do
    status = Map.get(resp, :status)
    headers = Map.get(resp, :headers, [])
    body = Map.get(resp, :body, %{})

    correlation_id = get_header(headers, "x-correlation-id")

    {code, message, details} =
      case body do
        %{"title" => title, "errors" => errors} ->
          {nil, title, errors}

        %{"title" => title, "detail" => detail} ->
          {nil, "#{title}: #{detail}", body}

        %{"message" => msg} ->
          {nil, msg, body}

        %{"error" => err} ->
          {err, err, body}

        _ ->
          {nil, "HTTP #{status}", body}
      end

    %__MODULE__{
      status: status,
      code: code,
      message: message || "Unknown error",
      details: details,
      request_id: request_id,
      correlation_id: correlation_id
    }
  end

  @doc """
  Builds a generic `%ClearBank.Error{}` from an exception or reason.
  """
  @spec from_exception(term()) :: t()
  def from_exception(%_{message: msg} = ex) do
    %__MODULE__{
      status: nil,
      message: msg,
      details: %{exception: inspect(ex)}
    }
  end

  def from_exception(reason) do
    %__MODULE__{
      status: nil,
      message: inspect(reason)
    }
  end

  @doc "Returns true if the error is retryable (5xx or 429)."
  @spec retryable?(t()) :: boolean()
  def retryable?(%__MODULE__{status: status}) when status in [429, 500, 503], do: true
  def retryable?(_), do: false

  defp get_header(headers, name) when is_list(headers) do
    case List.keyfind(headers, name, 0) do
      {_, value} -> value
      nil -> nil
    end
  end

  defp get_header(_, _), do: nil
end
