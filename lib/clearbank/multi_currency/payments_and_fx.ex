defmodule ClearBank.MultiCurrency.Payments do
  @moduledoc """
  Multi-currency international payment sending.

  Supports single and bulk high-value international payments via SWIFT
  and local clearing schemes, depending on currency and destination.

  ## Examples

      # Single international payment
      {:ok, result} = ClearBank.MultiCurrency.Payments.send(client, %{
        account_id: "mccy-acct-uuid",
        amount: "1000.00",
        currency: "EUR",
        creditor_name: "ACME GmbH",
        creditor_iban: "DE89370400440532013000",
        creditor_bic: "COBADEFFXXX",
        remittance_information: "Invoice EUR-001"
      })

      # Cancel a full batch
      {:ok, _} = ClearBank.MultiCurrency.Payments.cancel_batch(client, "batch-uuid")

      # Cancel a single payment in a batch
      {:ok, _} = ClearBank.MultiCurrency.Payments.cancel_payment(client, "batch-uuid", "e2e-id")
  """

  alias ClearBank.{Client, HTTP}

  @doc """
  Sends a single international payment.

  ## Required params

    * `:account_id` - source multi-currency account UUID
    * `:amount` - decimal string
    * `:currency` - ISO 4217 code
    * `:creditor_name` - beneficiary name
    * `:creditor_iban` - beneficiary IBAN (or `:creditor_account_number` + `:creditor_sort_code` for UK)
    * `:creditor_bic` - beneficiary BIC/SWIFT

  ## Optional params

    * `:end_to_end_id` - end-to-end reference
    * `:remittance_information` - payment narrative
    * `:creditor_address` - map with `:street_name`, `:town_name`, `:country`
  """
  @spec send(Client.t(), map()) :: HTTP.result()
  def send(%Client{} = client, params) when is_map(params) do
    body = %{
      "payments" => [build_payment_entry(params)]
    }

    HTTP.post(client, "/v1/mccy/payments", body)
  end

  @doc """
  Sends multiple international payments in a single batch.

  ## Params

    * `payments` - list of payment maps (same fields as `send/2`)
  """
  @spec send_bulk(Client.t(), [map()]) :: HTTP.result()
  def send_bulk(%Client{} = client, payments) when is_list(payments) do
    body = %{"payments" => Enum.map(payments, &build_payment_entry/1)}
    HTTP.post(client, "/v1/mccy/payments", body)
  end

  @doc """
  Cancels all payments in a batch by batch ID.
  """
  @spec cancel_batch(Client.t(), String.t()) :: HTTP.result()
  def cancel_batch(%Client{} = client, batch_id) when is_binary(batch_id) do
    HTTP.delete(client, "/v1/mccy/payments/#{batch_id}")
  end

  @doc """
  Cancels a single payment within a batch by end-to-end ID.
  """
  @spec cancel_payment(Client.t(), String.t(), String.t()) :: HTTP.result()
  def cancel_payment(%Client{} = client, batch_id, end_to_end_id) do
    HTTP.delete(client, "/v1/mccy/payments/#{batch_id}/#{end_to_end_id}")
  end

  @doc """
  Funds a multi-currency account (simulation only).

  This endpoint is only available in the simulation environment to inject
  test funds into an account.
  """
  @spec fund_account_sim(Client.t(), String.t(), map()) :: HTTP.result()
  def fund_account_sim(%Client{} = client, account_unique_id, params) do
    body = %{
      "amount" => Map.fetch!(params, :amount),
      "currency" => Map.fetch!(params, :currency)
    }

    HTTP.post(client, "/v1/mccy/inboundpayment/#{account_unique_id}", body)
  end

  # ---

  defp build_payment_entry(p) do
    %{
      "accountId" => Map.fetch!(p, :account_id),
      "amount" => Map.fetch!(p, :amount),
      "currencyCode" => Map.fetch!(p, :currency),
      "creditor" => build_creditor(p),
      "remittanceInformation" => Map.get(p, :remittance_information)
    }
    |> put_maybe("endToEndId", Map.get(p, :end_to_end_id))
  end

  defp build_creditor(p) do
    %{
      "name" => Map.fetch!(p, :creditor_name),
      "iban" => Map.get(p, :creditor_iban),
      "bic" => Map.get(p, :creditor_bic)
    }
    |> put_maybe("address", build_creditor_address(Map.get(p, :creditor_address)))
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp build_creditor_address(nil), do: nil

  defp build_creditor_address(addr) do
    %{
      "streetName" => Map.get(addr, :street_name),
      "townName" => Map.get(addr, :town_name),
      "country" => Map.get(addr, :country),
      "postCode" => Map.get(addr, :post_code)
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp put_maybe(map, _key, nil), do: map
  defp put_maybe(map, key, value), do: Map.put(map, key, value)
end

defmodule ClearBank.MultiCurrency.FxTrade do
  @moduledoc """
  FX Spot Trade — execute real-time foreign exchange conversions between two
  ClearBank currency accounts at the live market rate.

  ## Use when

  - You want to immediately convert at the current market rate.
  - You don't need to lock in a rate ahead of time.

  For pre-agreed quotes, see `ClearBank.MultiCurrency.FxTradeRfq`.

  ## Examples

      {:ok, result} = ClearBank.MultiCurrency.FxTrade.execute(client, %{
        sell_account_id: "eur-acct-uuid",
        buy_account_id: "gbp-acct-uuid",
        sell_currency: "EUR",
        buy_currency: "GBP",
        sell_amount: "10000.00"
      })
  """

  alias ClearBank.{Client, HTTP}

  @doc """
  Executes a spot FX trade.

  ## Required params

    * `:sell_account_id` - account to debit (sell currency)
    * `:buy_account_id` - account to credit (buy currency)
    * `:sell_currency` - ISO 4217 sell currency
    * `:buy_currency` - ISO 4217 buy currency

  Provide exactly one of:
    * `:sell_amount` - fixed sell amount
    * `:buy_amount` - fixed buy amount
  """
  @spec execute(Client.t(), map()) :: HTTP.result()
  def execute(%Client{} = client, params) when is_map(params) do
    body =
      %{
        "sellAccountId" => Map.fetch!(params, :sell_account_id),
        "buyAccountId" => Map.fetch!(params, :buy_account_id),
        "sellCurrency" => Map.fetch!(params, :sell_currency),
        "buyCurrency" => Map.fetch!(params, :buy_currency)
      }
      |> put_maybe("sellAmount", Map.get(params, :sell_amount))
      |> put_maybe("buyAmount", Map.get(params, :buy_amount))
      |> put_maybe("endToEndId", Map.get(params, :end_to_end_id))

    HTTP.post(client, "/v1/fx/trades", body)
  end

  defp put_maybe(map, _key, nil), do: map
  defp put_maybe(map, key, value), do: Map.put(map, key, value)
end

defmodule ClearBank.MultiCurrency.FxTradeRfq do
  @moduledoc """
  FX Request for Quote (RFQ) — lock in a firm exchange rate before executing.

  ## Workflow

  1. Call `request_quote/2` to get a firm rate with a quote ID.
  2. Review the quoted rate and expiry.
  3. Call `execute_quote/2` to trade at that rate, or `reject_quote/2` to cancel.

  Quotes expire — check `expiresAt` in the response and execute before then.

  ## Examples

      {:ok, quote} = ClearBank.MultiCurrency.FxTradeRfq.request_quote(client, %{
        sell_account_id: "eur-acct-uuid",
        buy_account_id: "gbp-acct-uuid",
        sell_currency: "EUR",
        buy_currency: "GBP",
        sell_amount: "50000.00"
      })

      quote_id = quote["quoteId"]

      {:ok, _} = ClearBank.MultiCurrency.FxTradeRfq.execute_quote(client, quote_id)
  """

  alias ClearBank.{Client, HTTP}

  @doc """
  Requests a firm FX quote (RFQ).

  ## Required params

    * `:sell_account_id`, `:buy_account_id`
    * `:sell_currency`, `:buy_currency`
    * `:sell_amount` or `:buy_amount`
  """
  @spec request_quote(Client.t(), map()) :: HTTP.result()
  def request_quote(%Client{} = client, params) when is_map(params) do
    body =
      %{
        "sellAccountId" => Map.fetch!(params, :sell_account_id),
        "buyAccountId" => Map.fetch!(params, :buy_account_id),
        "sellCurrency" => Map.fetch!(params, :sell_currency),
        "buyCurrency" => Map.fetch!(params, :buy_currency)
      }
      |> put_maybe("sellAmount", Map.get(params, :sell_amount))
      |> put_maybe("buyAmount", Map.get(params, :buy_amount))

    HTTP.post(client, "/v1/fx/quotes", body)
  end

  @doc """
  Executes a previously quoted FX trade.

  ## Examples

      {:ok, result} = ClearBank.MultiCurrency.FxTradeRfq.execute_quote(client, "quote-uuid")
  """
  @spec execute_quote(Client.t(), String.t()) :: HTTP.result()
  def execute_quote(%Client{} = client, quote_id) when is_binary(quote_id) do
    HTTP.post(client, "/v1/fx/quotes/#{quote_id}/execute", %{})
  end

  @doc """
  Rejects/cancels a quote without executing.

  ## Examples

      {:ok, _} = ClearBank.MultiCurrency.FxTradeRfq.reject_quote(client, "quote-uuid")
  """
  @spec reject_quote(Client.t(), String.t()) :: HTTP.result()
  def reject_quote(%Client{} = client, quote_id) when is_binary(quote_id) do
    HTTP.delete(client, "/v1/fx/quotes/#{quote_id}")
  end

  defp put_maybe(map, _key, nil), do: map
  defp put_maybe(map, key, value), do: Map.put(map, key, value)
end

defmodule ClearBank.MultiCurrency.SepaCreditTransfer do
  @moduledoc """
  SEPA Credit Transfer UK (SCT UK) — send and return euro payments
  via the SEPA Credit Transfer scheme from within the UK.

  Post-Brexit, this enables ClearBank UK clients to participate in
  euro SEPA payments using the SCT UK framework.

  ## Key facts

  - **Currency:** EUR only
  - **Scheme:** SEPA Credit Transfer
  - **Endpoint:** ISO 20022 pacs.008 (customer) and pacs.004 (return)

  ## Examples

      {:ok, result} = ClearBank.MultiCurrency.SepaCreditTransfer.send(client, %{
        debtor_account_id: "eur-acct-uuid",
        amount: "2500.00",
        creditor_name: "Müller GmbH",
        creditor_iban: "DE89370400440532013000",
        creditor_bic: "COBADEFFXXX",
        remittance_information: "Invoice DE-2024-001"
      })
  """

  alias ClearBank.{Client, HTTP}

  @doc """
  Sends a SEPA Credit Transfer UK payment.

  ## Required params

    * `:debtor_account_id` - source EUR account UUID
    * `:amount` - decimal string (EUR)
    * `:creditor_name` - beneficiary name
    * `:creditor_iban` - beneficiary IBAN
    * `:creditor_bic` - beneficiary BIC
    * `:remittance_information` - payment reference

  ## Optional params

    * `:end_to_end_id` - end-to-end reference
    * `:instruction_id` - unique instruction ID
  """
  @spec send(Client.t(), map()) :: HTTP.result()
  def send(%Client{} = client, params) when is_map(params) do
    body =
      %{
        "debtorAccountId" => Map.fetch!(params, :debtor_account_id),
        "instructedAmount" => %{
          "amount" => Map.fetch!(params, :amount),
          "currency" => "EUR"
        },
        "creditor" => %{
          "name" => Map.fetch!(params, :creditor_name),
          "iban" => Map.fetch!(params, :creditor_iban),
          "bic" => Map.fetch!(params, :creditor_bic)
        },
        "remittanceInformation" => Map.fetch!(params, :remittance_information)
      }
      |> put_maybe("endToEndId", Map.get(params, :end_to_end_id))
      |> put_maybe("instructionId", Map.get(params, :instruction_id))

    HTTP.post(client, "/payments/sepa-credit-transfer/v2/customer-payments", body)
  end

  @doc """
  Returns a received SEPA Credit Transfer UK payment.

  ## Required params

    * `:original_instruction_id` - instruction ID of the original payment
    * `:debtor_account_id` - account to return from
    * `:return_reason_code` - ISO 20022 reason code (e.g. `"AC03"`, `"CUST"`)
    * `:amount` - return amount
  """
  @spec return_payment(Client.t(), map()) :: HTTP.result()
  def return_payment(%Client{} = client, params) when is_map(params) do
    body = %{
      "originalInstructionId" => Map.fetch!(params, :original_instruction_id),
      "debtorAccountId" => Map.fetch!(params, :debtor_account_id),
      "returnReasonCode" => Map.fetch!(params, :return_reason_code),
      "instructedAmount" => %{
        "amount" => Map.fetch!(params, :amount),
        "currency" => "EUR"
      }
    }

    HTTP.post(client, "/payments/sepa-credit-transfer/v2/return-payments", body)
  end

  defp put_maybe(map, _key, nil), do: map
  defp put_maybe(map, key, value), do: Map.put(map, key, value)
end
