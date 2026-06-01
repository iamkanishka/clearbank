defmodule ClearBank.Accounts.Transactions do
  @moduledoc """
  Transaction data retrieval for GBP real and virtual accounts.

  Transactions are created by inbound and outbound payments.
  Use `list_all/2` for institution-wide reporting, or account-scoped
  functions for per-account transaction history.
  """

  alias ClearBank.{Client, HTTP, Types}

  @doc """
  Returns all transactions across the institution.

  ## Options

    * `:page_number` - page (default: 1)
    * `:page_size` - results per page (default: 50)
    * `:start_date` - ISO 8601 datetime filter
    * `:end_date` - ISO 8601 datetime filter

  ## Examples

      {:ok, txns} = ClearBank.Accounts.Transactions.list_all(client)
  """
  @spec list_all(Client.t(), keyword()) :: HTTP.result()
  def list_all(%Client{} = client, opts \\ []) do
    params = filter_params(opts, [:page_number, :page_size, :start_date, :end_date])
    HTTP.get(client, Types.build_path("/v2/Transactions", params))
  end

  @doc """
  Returns all transactions for a specific real account.

  ## Options

    * `:page_number`, `:page_size`, `:start_date`, `:end_date`

  ## Examples

      {:ok, txns} = ClearBank.Accounts.Transactions.list(client, "acct-uuid")
  """
  @spec list(Client.t(), String.t(), keyword()) :: HTTP.result()
  def list(%Client{} = client, account_id, opts \\ []) do
    params = filter_params(opts, [:page_number, :page_size, :start_date, :end_date])
    HTTP.get(client, Types.build_path("/v2/Accounts/#{account_id}/Transactions", params))
  end

  @doc """
  Returns a specific transaction on a real account.

  ## Examples

      {:ok, txn} = ClearBank.Accounts.Transactions.get(client, "acct-uuid", "txn-uuid")
  """
  @spec get(Client.t(), String.t(), String.t()) :: HTTP.result()
  def get(%Client{} = client, account_id, transaction_id) do
    HTTP.get(client, "/v2/Accounts/#{account_id}/Transactions/#{transaction_id}")
  end

  @doc """
  Returns all transactions for a virtual account.

  ## Options

    * `:page_number`, `:page_size`, `:start_date`, `:end_date`

  ## Examples

      {:ok, txns} = ClearBank.Accounts.Transactions.list_virtual(client, "acct-uuid", "virt-uuid")
  """
  @spec list_virtual(Client.t(), String.t(), String.t(), keyword()) :: HTTP.result()
  def list_virtual(%Client{} = client, account_id, virtual_account_id, opts \\ []) do
    params = filter_params(opts, [:page_number, :page_size, :start_date, :end_date])

    HTTP.get(
      client,
      Types.build_path(
        "/v1/Accounts/#{account_id}/Virtual/#{virtual_account_id}/Transactions",
        params
      )
    )
  end

  # ---

  defp filter_params(opts, allowed_keys) do
    opts
    |> Keyword.take(allowed_keys)
    |> Map.new()
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end
end
