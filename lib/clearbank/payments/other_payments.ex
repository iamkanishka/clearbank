defmodule ClearBank.Payments.Cheques do
  @moduledoc """
  Cheque deposit via the Image Cheque Clearing System (ICS).

  ClearBank supports inbound cheque deposits by submitting a cheque image.
  The image must meet ICS quality standards.

  ## Settlement

  ICS cheques settle on Day 2 (next business day) for most cheques.
  """

  alias ClearBank.{Client, HTTP}

  @doc """
  Submits a cheque image deposit.

  ## Required params

    * `:account_id` - destination account UUID
    * `:amount` - decimal string amount on the cheque
    * `:currency` - `"GBP"`
    * `:cheque_image_front` - Base64-encoded front image (TIFF or PNG)
    * `:cheque_image_back` - Base64-encoded back image
    * `:micr_line` - MICR line string from the bottom of the cheque

  ## Optional params

    * `:payee_name` - name of the payee on the cheque
    * `:cheque_number` - cheque serial number

  ## Examples

      {:ok, result} = ClearBank.Payments.Cheques.submit_deposit(client, %{
        account_id: "acct-uuid",
        amount: "500.00",
        currency: "GBP",
        cheque_image_front: Base.encode64(front_tiff),
        cheque_image_back: Base.encode64(back_tiff),
        micr_line: "000123|040004|12345678|"
      })
  """
  @spec submit_deposit(Client.t(), map()) :: HTTP.result()
  def submit_deposit(%Client{} = client, params) when is_map(params) do
    body =
      %{
        "accountId" => Map.fetch!(params, :account_id),
        "amount" => Map.fetch!(params, :amount),
        "currency" => Map.get(params, :currency, "GBP"),
        "chequeImageFront" => Map.fetch!(params, :cheque_image_front),
        "chequeImageBack" => Map.fetch!(params, :cheque_image_back),
        "micrLine" => Map.fetch!(params, :micr_line)
      }
      |> put_maybe("payeeName", Map.get(params, :payee_name))
      |> put_maybe("chequeNumber", Map.get(params, :cheque_number))

    HTTP.post(client, "/payments/cheques/v1/submit-deposit", body)
  end

  defp put_maybe(map, _key, nil), do: map
  defp put_maybe(map, key, value), do: Map.put(map, key, value)
end

defmodule ClearBank.Payments.CrossBorder do
  @moduledoc """
  GBP Cross-Border Payments — sending GBP internationally via SWIFT/correspondent banking.

  > **⚠️ Deprecation notice:**
  > This endpoint (`/payments/cross-border-sterling/v3/payments`) is deprecated as of
  > **13 May 2026** and reaches end-of-life on **13 November 2026**.
  > Migrate to the Multi-currency payments API before that date.

  ## Examples

      {:ok, result} = ClearBank.Payments.CrossBorder.send(client, %{
        account_id: "acct-uuid",
        amount: "1000.00",
        currency: "GBP",
        creditor_name: "ACME Corp",
        creditor_iban: "DE89370400440532013000",
        creditor_bic: "COBADEFFXXX",
        remittance_information: "Invoice 1234"
      })
  """

  alias ClearBank.{Client, HTTP}

  @deprecated "Use ClearBank.MultiCurrency.Payments instead. EOL: 13 Nov 2026."

  @doc """
  Sends a GBP cross-border payment.

  **Deprecated.** Use `ClearBank.MultiCurrency.Payments.send/2` instead.
  """
  @spec send(Client.t(), map()) :: HTTP.result()
  def send(%Client{} = client, params) when is_map(params) do
    body = %{
      "accountId" => Map.fetch!(params, :account_id),
      "amount" => Map.fetch!(params, :amount),
      "currency" => Map.get(params, :currency, "GBP"),
      "creditor" => %{
        "name" => Map.fetch!(params, :creditor_name),
        "iban" => Map.get(params, :creditor_iban),
        "bic" => Map.get(params, :creditor_bic)
      },
      "remittanceInformation" => Map.get(params, :remittance_information)
    }

    HTTP.post(client, "/payments/cross-border-sterling/v3/payments", body)
  end
end

defmodule ClearBank.Payments.ConfirmationOfPayee do
  @moduledoc """
  Confirmation of Payee (CoP) — pre-payment name checking service.

  CoP allows you to verify that an account holder's name matches the sort code
  and account number before sending a payment. This is mandatory for PSPs
  under UK Payment Systems Regulator (PSR) rules.

  ## Match results

  The API returns one of:
  - `"MATC"` — full match
  - `"CLOSE"` — close match (possible typo)
  - `"NOMATCH"` — no match
  - `"INAM"` — account type mismatch (business vs. personal)
  - `"PANM"` — partial match

  ## Opting accounts out of CoP

  You can opt individual real or virtual accounts out of CoP (inbound checks),
  for example for operational/internal accounts.

  ## Examples

      # Check a payee before sending
      {:ok, result} = ClearBank.Payments.ConfirmationOfPayee.check(client, %{
        account_type: "Personal",
        account_name: "Jane Smith",
        sort_code: "040004",
        account_number: "12345678"
      })

      # => %{"matchResult" => "MATC", ...}
  """

  alias ClearBank.{Client, HTTP}

  @doc """
  Sends an outbound CoP name verification request.

  ## Required params

    * `:account_name` - name to check
    * `:sort_code` - 6-digit sort code
    * `:account_number` - 8-digit account number

  ## Optional params

    * `:account_type` - `"Personal"` | `"Business"` (default: `"Personal"`)
    * `:secondary_reference` - secondary reference data (for building societies)

  ## Examples

      {:ok, result} = ClearBank.Payments.ConfirmationOfPayee.check(client, %{
        account_name: "Jane Smith",
        sort_code: "040004",
        account_number: "12345678",
        account_type: "Personal"
      })
  """
  @spec check(Client.t(), map()) :: HTTP.result()
  def check(%Client{} = client, params) when is_map(params) do
    body =
      %{
        "accountType" => Map.get(params, :account_type, "Personal"),
        "accountName" => Map.fetch!(params, :account_name),
        "sortCode" => Map.fetch!(params, :sort_code),
        "accountNumber" => Map.fetch!(params, :account_number)
      }
      |> put_maybe("secondaryReference", Map.get(params, :secondary_reference))

    HTTP.post(client, "/v1/Cop/outbound/name-verification", body)
  end

  @doc """
  Opts a real account out of inbound CoP checks.

  ## Examples

      {:ok, _} = ClearBank.Payments.ConfirmationOfPayee.opt_out_account(client, "acct-uuid")
  """
  @spec opt_out_account(Client.t(), String.t()) :: HTTP.result()
  def opt_out_account(%Client{} = client, account_id) when is_binary(account_id) do
    HTTP.put(client, "/v1/Cop/opt/accounts/#{account_id}", %{"optOut" => true})
  end

  @doc """
  Opts a virtual account out of inbound CoP checks.

  ## Examples

      {:ok, _} = ClearBank.Payments.ConfirmationOfPayee.opt_out_virtual(client, "acct-uuid", "virt-uuid")
  """
  @spec opt_out_virtual(Client.t(), String.t(), String.t()) :: HTTP.result()
  def opt_out_virtual(%Client{} = client, account_id, virtual_account_id) do
    HTTP.put(
      client,
      "/v1/Cop/opt/accounts/#{account_id}/virtual/#{virtual_account_id}",
      %{"optOut" => true}
    )
  end

  defp put_maybe(map, _key, nil), do: map
  defp put_maybe(map, key, value), do: Map.put(map, key, value)
end
