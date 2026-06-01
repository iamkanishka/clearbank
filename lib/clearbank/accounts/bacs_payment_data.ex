defmodule ClearBank.Accounts.BacsPaymentData do
  @moduledoc """
  Bacs-specific payment data retrieval.

  Covers Direct Debit collections and returns for both real and virtual accounts.
  """

  alias ClearBank.{Client, HTTP, Types}

  @doc """
  Returns collected Direct Debit payments for a mandate on a real account.

  ## Options

    * `:page_number`, `:page_size`

  ## Examples

      {:ok, collections} = ClearBank.Accounts.BacsPaymentData.list_collections(
        client, "acct-uuid", "mandate-uuid"
      )
  """
  @spec list_collections(Client.t(), String.t(), String.t(), keyword()) :: HTTP.result()
  def list_collections(%Client{} = client, account_id, mandate_id, opts \\ []) do
    params = Map.new(opts) |> Map.take([:page_number, :page_size])

    HTTP.get(
      client,
      Types.build_path(
        "/v2/Accounts/#{account_id}/Mandates/#{mandate_id}/Collections",
        params
      )
    )
  end

  @doc """
  Returns returned Bacs payments for a mandate on a real account.

  ## Options

    * `:page_number`, `:page_size`

  ## Examples

      {:ok, returns} = ClearBank.Accounts.BacsPaymentData.list_returns(
        client, "acct-uuid", "mandate-uuid"
      )
  """
  @spec list_returns(Client.t(), String.t(), String.t(), keyword()) :: HTTP.result()
  def list_returns(%Client{} = client, account_id, mandate_id, opts \\ []) do
    params = Map.new(opts) |> Map.take([:page_number, :page_size])

    HTTP.get(
      client,
      Types.build_path(
        "/v1/Accounts/#{account_id}/Mandates/#{mandate_id}/Returns",
        params
      )
    )
  end
end
