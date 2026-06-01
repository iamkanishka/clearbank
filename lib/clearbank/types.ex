defmodule ClearBank.Types do
  @moduledoc """
  Shared type definitions and helper guards used across `clearbank`.
  """

  @typedoc "ISO 4217 currency code, e.g. GBP, EUR, USD"
  @type currency_code :: String.t()

  @typedoc "Monetary amount as a Decimal-compatible string, e.g. 1000.00"
  @type amount :: String.t()

  @typedoc "UUID v4 string"
  @type uuid :: String.t()

  @typedoc "ISO 8601 datetime string"
  @type datetime :: String.t()

  @typedoc "Sort code — 6 digits, no dashes, e.g. 040004"
  @type sort_code :: String.t()

  @typedoc "Account number — 8 digits"
  @type account_number :: String.t()

  @typedoc "IBAN string"
  @type iban :: String.t()

  @typedoc "BIC / SWIFT code"
  @type bic :: String.t()

  @typedoc "Paginated response wrapper"
  @type paginated(t) :: %{
          data: [t],
          total_count: non_neg_integer(),
          page_number: pos_integer(),
          page_size: pos_integer()
        }

  @typedoc "Standard pagination params"
  @type pagination_params :: %{
          optional(:page_number) => pos_integer(),
          optional(:page_size) => pos_integer()
        }

  @doc """
  Converts a keyword list or map to a query string, dropping nil values.
  """
  @spec to_query(map() | keyword()) :: String.t()
  def to_query(params) when is_map(params) do
    params
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> URI.encode_query()
  end

  def to_query(params) when is_list(params) do
    params |> Map.new() |> to_query()
  end

  @doc """
  Appends query params to a path, only if params is non-empty.
  """
  @spec build_path(String.t(), map() | keyword()) :: String.t()
  def build_path(path, params) do
    case to_query(params) do
      "" -> path
      qs -> "#{path}?#{qs}"
    end
  end
end
