defmodule ClearBank.Payments.Chaps do
  @moduledoc """
  CHAPS (Clearing House Automated Payment System) — high-value, same-day GBP payments
  settling via the Bank of England's RTGS system.

  ## Key facts

  - **No upper limit** — suitable for property purchases, large corporate payments
  - **Settlement:** Same business day (Bank of England operating hours only)
  - **Cut-off:** Check Bank of England RTGS operating schedule
  - **Schema:** ISO 20022 pacs.008 (customer payments)

  ## Required creditor fields

  ClearBank uses ISO 20022 structured address for CHAPS. The `:creditor_address`
  must include `:street_name`, `:building_number`, `:post_code`, `:town_name`,
  and `:country` (ISO 3166-1 alpha-2).

  ## Examples

      {:ok, result} = ClearBank.Payments.Chaps.send(client, %{
        debtor_account_id: "acct-uuid",
        amount: "500000.00",
        currency: "GBP",
        creditor_name: "Conveyancing Ltd",
        creditor_sort_code: "200000",
        creditor_account_number: "55779911",
        creditor_address: %{
          street_name: "High Street",
          building_number: "1",
          post_code: "SW1A 1AA",
          town_name: "London",
          country: "GB"
        },
        remittance_information: "PROP PURCHASE REF XYZ"
      })
  """

  alias ClearBank.{Client, HTTP}

  @doc """
  Sends a CHAPS customer credit transfer (pacs.008).

  ## Required params

    * `:debtor_account_id` - source account UUID
    * `:amount` - decimal string
    * `:currency` - `"GBP"`
    * `:creditor_name` - recipient name
    * `:creditor_sort_code` - 6-digit sort code
    * `:creditor_account_number` - 8-digit account number
    * `:creditor_address` - structured address map (see module docs)
    * `:remittance_information` - payment narrative

  ## Optional params

    * `:end_to_end_id` - your end-to-end reference
    * `:instruction_id` - unique instruction ID
    * `:debtor_name` - override debtor name
    * `:debtor_address` - structured address map for debtor
  """
  @spec send(Client.t(), map()) :: HTTP.result()
  def send(%Client{} = client, params) when is_map(params) do
    body = build_body(params)
    HTTP.post(client, "/payments/chaps/v5/customer-payments", body)
  end

  @doc """
  Returns a received CHAPS payment.

  ## Required params

    * `:original_instruction_id` - instruction ID of the payment to return
    * `:debtor_account_id` - account from which to return the funds
    * `:return_reason_code` - ISO 20022 reason code (e.g. `"AC03"`, `"CUST"`)
    * `:amount` - amount to return
    * `:currency` - `"GBP"`
  """
  @spec return_payment(Client.t(), map()) :: HTTP.result()
  def return_payment(%Client{} = client, params) when is_map(params) do
    body = %{
      "originalInstructionId" => Map.fetch!(params, :original_instruction_id),
      "debtorAccountId" => Map.fetch!(params, :debtor_account_id),
      "returnReasonCode" => Map.fetch!(params, :return_reason_code),
      "instructedAmount" => %{
        "amount" => Map.fetch!(params, :amount),
        "currency" => Map.get(params, :currency, "GBP")
      }
    }

    HTTP.post(client, "/payments/chaps/v5/return-payments", body)
  end

  # ---

  defp build_body(params) do
    addr = Map.get(params, :creditor_address, %{})

    %{
      "debtorAccountId" => Map.fetch!(params, :debtor_account_id),
      "instructedAmount" => %{
        "amount" => Map.fetch!(params, :amount),
        "currency" => Map.get(params, :currency, "GBP")
      },
      "creditor" => %{
        "name" => Map.fetch!(params, :creditor_name),
        "account" => %{
          "sortCode" => Map.fetch!(params, :creditor_sort_code),
          "accountNumber" => Map.fetch!(params, :creditor_account_number)
        },
        "address" => build_address(addr)
      },
      "remittanceInformation" => Map.fetch!(params, :remittance_information)
    }
    |> put_maybe("endToEndId", Map.get(params, :end_to_end_id))
    |> put_maybe("instructionId", Map.get(params, :instruction_id))
    |> put_maybe_nested("debtor", "name", Map.get(params, :debtor_name))
  end

  defp build_address(addr) do
    %{
      "streetName" => Map.get(addr, :street_name),
      "buildingNumber" => Map.get(addr, :building_number),
      "postCode" => Map.get(addr, :post_code),
      "townName" => Map.get(addr, :town_name),
      "country" => Map.get(addr, :country)
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp put_maybe(map, _key, nil), do: map
  defp put_maybe(map, key, value), do: Map.put(map, key, value)

  defp put_maybe_nested(map, _top, _inner, nil), do: map

  defp put_maybe_nested(map, top_key, inner_key, value) do
    nested = Map.get(map, top_key, %{}) |> Map.put(inner_key, value)
    Map.put(map, top_key, nested)
  end
end
