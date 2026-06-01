defmodule ClearBank.Payments.Bacs do
  @moduledoc """
  Bacs payment operations — primarily returning Bacs Direct Credits
  and Direct Debit payments.

  Bacs uses a 3-day settlement cycle:
  - Day 1: Submit
  - Day 2: Processing
  - Day 3: Settlement

  ## Examples

      # Return a Bacs payment received on a real account
      {:ok, _} = ClearBank.Payments.Bacs.return(client, "acct-uuid", %{
        transaction_id: "txn-uuid",
        reason_code: "0"
      })
  """

  alias ClearBank.{Client, HTTP}

  @doc """
  Returns a Bacs payment received on a real account.

  ## Required params

    * `:transaction_id` - UUID of the transaction to return
    * `:reason_code` - Bacs return reason code (e.g. `"0"` = not provided)

  ## Examples

      {:ok, _} = ClearBank.Payments.Bacs.return(client, "acct-uuid", %{
        transaction_id: "txn-uuid",
        reason_code: "0"
      })
  """
  @spec return(Client.t(), String.t(), map()) :: HTTP.result()
  def return(%Client{} = client, account_id, params) when is_binary(account_id) do
    body = %{
      "transactionId" => Map.fetch!(params, :transaction_id),
      "reasonCode" => Map.fetch!(params, :reason_code)
    }

    HTTP.post(client, "/v1/Accounts/#{account_id}/Transactions/Returns", body)
  end

  @doc """
  Returns a Bacs payment received on a virtual account.

  ## Examples

      {:ok, _} = ClearBank.Payments.Bacs.return_virtual(client, "acct-uuid", "virt-uuid", %{
        transaction_id: "txn-uuid",
        reason_code: "0"
      })
  """
  @spec return_virtual(Client.t(), String.t(), String.t(), map()) :: HTTP.result()
  def return_virtual(%Client{} = client, account_id, virtual_account_id, params) do
    body = %{
      "transactionId" => Map.fetch!(params, :transaction_id),
      "reasonCode" => Map.fetch!(params, :reason_code)
    }

    HTTP.post(
      client,
      "/v1/Accounts/#{account_id}/Virtual/#{virtual_account_id}/Transactions/Returns",
      body
    )
  end
end

defmodule ClearBank.Payments.BacsDirectDebit do
  @moduledoc """
  Bacs Direct Debit Instructions (DDIs) — create, retrieve, and cancel
  Direct Debit mandates on real and virtual accounts.

  Direct Debit Instructions represent authorisation from your customer
  to collect payments from their account. They can be:
  - Created via the paper/electronic DDI flow
  - Migrated from another Service User

  ## Service User Numbers (SUNs)

  Each DDI is associated with a Service User Number which identifies you
  as the originator to Bacs. Your SUN must be configured in the ClearBank Portal.

  ## Examples

      # Create a DDI on a real account
      {:ok, ddi} = ClearBank.Payments.BacsDirectDebit.create(client, "acct-uuid", %{
        service_user_number: "123456",
        reference: "CUST-001",
        payer_name: "Alice Smith",
        payer_sort_code: "040004",
        payer_account_number: "12345678"
      })
  """

  alias ClearBank.{Client, HTTP, Types}

  # ---- Real account DDIs ----

  @doc """
  Creates a Direct Debit Instruction on a real account.

  ## Required params

    * `:service_user_number` - your Bacs SUN
    * `:reference` - DDI reference (shown on customer's bank statement)
    * `:payer_name` - account holder name of the payer
    * `:payer_sort_code` - payer's sort code
    * `:payer_account_number` - payer's account number

  ## Optional params

    * `:originator_name` - override originator name
    * `:account_type` - `"Personal"` | `"Business"` (default: `"Personal"`)
  """
  @spec create(Client.t(), String.t(), map()) :: HTTP.result()
  def create(%Client{} = client, account_id, params) when is_binary(account_id) do
    body = build_ddi_body(params)
    HTTP.post(client, "/v1/Accounts/#{account_id}/Mandates", body)
  end

  @doc """
  Returns all Direct Debit Instructions for a real account.

  ## Options

    * `:page_number`, `:page_size`
  """
  @spec list(Client.t(), String.t(), keyword()) :: HTTP.result()
  def list(%Client{} = client, account_id, opts \\ []) do
    params = Map.new(opts) |> Map.take([:page_number, :page_size])
    HTTP.get(client, Types.build_path("/v2/Accounts/#{account_id}/Mandates", params))
  end

  @doc """
  Returns a specific Direct Debit Instruction on a real account.
  """
  @spec get(Client.t(), String.t(), String.t()) :: HTTP.result()
  def get(%Client{} = client, account_id, mandate_id) do
    HTTP.get(client, "/v1/Accounts/#{account_id}/Mandates/#{mandate_id}")
  end

  @doc """
  Cancels a Direct Debit Instruction on a real account.
  """
  @spec cancel(Client.t(), String.t(), String.t()) :: HTTP.result()
  def cancel(%Client{} = client, account_id, mandate_id) do
    HTTP.delete(client, "/v1/Accounts/#{account_id}/Mandates/#{mandate_id}")
  end

  # ---- Virtual account DDIs ----

  @doc """
  Creates a Direct Debit Instruction on a virtual account.
  """
  @spec create_virtual(Client.t(), String.t(), String.t(), map()) :: HTTP.result()
  def create_virtual(%Client{} = client, account_id, virtual_account_id, params) do
    body = build_ddi_body(params)
    HTTP.post(client, "/v1/Accounts/#{account_id}/Virtual/#{virtual_account_id}/Mandates", body)
  end

  @doc """
  Returns all DDIs for a virtual account.
  """
  @spec list_virtual(Client.t(), String.t(), String.t(), keyword()) :: HTTP.result()
  def list_virtual(%Client{} = client, account_id, virtual_account_id, opts \\ []) do
    params = Map.new(opts) |> Map.take([:page_number, :page_size])

    HTTP.get(
      client,
      Types.build_path(
        "/v1/Accounts/#{account_id}/Virtual/#{virtual_account_id}/Mandates",
        params
      )
    )
  end

  @doc """
  Cancels a DDI on a virtual account.
  """
  @spec cancel_virtual(Client.t(), String.t(), String.t(), String.t()) :: HTTP.result()
  def cancel_virtual(%Client{} = client, account_id, virtual_account_id, mandate_id) do
    HTTP.delete(
      client,
      "/v1/Accounts/#{account_id}/Virtual/#{virtual_account_id}/Mandates/#{mandate_id}"
    )
  end

  # ---

  defp build_ddi_body(params) do
    %{
      "serviceUserNumber" => Map.fetch!(params, :service_user_number),
      "reference" => Map.fetch!(params, :reference),
      "payerDetails" => %{
        "name" => Map.fetch!(params, :payer_name),
        "sortCode" => Map.fetch!(params, :payer_sort_code),
        "accountNumber" => Map.fetch!(params, :payer_account_number),
        "accountType" => Map.get(params, :account_type, "Personal")
      }
    }
    |> put_maybe("originatorName", Map.get(params, :originator_name))
  end

  defp put_maybe(map, _key, nil), do: map
  defp put_maybe(map, key, value), do: Map.put(map, key, value)
end
