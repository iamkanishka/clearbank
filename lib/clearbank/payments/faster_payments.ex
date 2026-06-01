defmodule ClearBank.Payments.FasterPayments do
  @moduledoc """
  Faster Payments Service (FPS) — the UK's 24/7/365 real-time payment rail.

  ## Key facts

  - **Limit:** £1,000,000 per payment
  - **Speed:** Near-instant (typically < 90 seconds)
  - **Availability:** 24/7/365
  - **Confirmation:** Via `TransactionSettled` webhook

  ## APP Scam routing

  The `:enforce_send_to_scheme` option controls liability:
  - `false` (default) — if recipient is a ClearBank client, routed as an internal
    transfer. Faster and not subject to APP scam reimbursement rules.
  - `true` — always routed via the FPS scheme. Subject to Pay.UK APP scam
    reimbursement liability.

  ## Abusive message filtering

  References are screened against the Pay.UK abusive message filter list.
  Entries that match are blanked rather than rejected.

  ## Payment types

  - `:sip` — Single Immediate Payment (default)
  - `:sop` — Standing Order Payment
  - `:fdp` — Forward-Dated Payment

  ## Examples

      # Single payment
      {:ok, result} = ClearBank.Payments.FasterPayments.send(client, %{
        account_id: "acct-uuid",
        amount: "100.00",
        currency: "GBP",
        destination_sort_code: "040004",
        destination_account_number: "12345678",
        destination_account_name: "Jane Smith",
        reference: "INV-001"
      })

      # Bulk payment
      {:ok, result} = ClearBank.Payments.FasterPayments.send_bulk(client, "acct-uuid", [
        %{amount: "50.00", destination_sort_code: "040004", ...},
        %{amount: "75.00", destination_sort_code: "060400", ...}
      ])
  """

  alias ClearBank.{Client, HTTP}

  @type payment :: %{
          required(:amount) => String.t(),
          required(:currency) => String.t(),
          required(:destination_sort_code) => String.t(),
          required(:destination_account_number) => String.t(),
          required(:destination_account_name) => String.t(),
          optional(:reference) => String.t(),
          optional(:payment_type) => :sip | :sop | :fdp,
          optional(:enforce_send_to_scheme) => boolean(),
          optional(:end_to_end_id) => String.t()
        }

  @doc """
  Sends a single Faster Payment.

  ## Required fields

    * `:account_id` - source account UUID
    * `:amount` - decimal string, e.g. `"100.00"`
    * `:currency` - `"GBP"`
    * `:destination_sort_code` - 6-digit sort code
    * `:destination_account_number` - 8-digit account number
    * `:destination_account_name` - payee name (max 140 chars; truncated to 35 at scheme)

  ## Optional fields

    * `:reference` - payment reference (max 35 chars; truncated to 18 at scheme)
    * `:payment_type` - `:sip` | `:sop` | `:fdp` (default: `:sip`)
    * `:enforce_send_to_scheme` - boolean (default: `false`)
    * `:end_to_end_id` - your internal end-to-end reference

  ## Examples

      {:ok, resp} = ClearBank.Payments.FasterPayments.send(client, %{
        account_id: "acct-uuid",
        amount: "250.00",
        currency: "GBP",
        destination_sort_code: "040004",
        destination_account_number: "12345678",
        destination_account_name: "Jane Smith",
        reference: "SALARY-MAY"
      })
  """
  @spec send(Client.t(), map()) :: HTTP.result()
  def send(%Client{} = client, payment) when is_map(payment) do
    body = build_single_body(payment)
    HTTP.post(client, "/v3/Payments/FPS", body)
  end

  @doc """
  Sends multiple Faster Payments in one request (bulk).

  ## Params

    * `account_id` - source account UUID (applies to all payments in batch)
    * `payments` - list of payment maps (same fields as `send/2` minus `:account_id`)

  ## Examples

      {:ok, resp} = ClearBank.Payments.FasterPayments.send_bulk(client, "acct-uuid", [
        %{amount: "100.00", currency: "GBP", destination_sort_code: "040004",
          destination_account_number: "12345678", destination_account_name: "Alice"},
        %{amount: "200.00", currency: "GBP", destination_sort_code: "060400",
          destination_account_number: "87654321", destination_account_name: "Bob"}
      ])
  """
  @spec send_bulk(Client.t(), String.t(), [map()]) :: HTTP.result()
  def send_bulk(%Client{} = client, account_id, payments)
      when is_binary(account_id) and is_list(payments) do
    body = %{
      "accountId" => account_id,
      "payments" =>
        Enum.map(payments, fn p ->
          p |> Map.put(:account_id, account_id) |> build_payment_entry()
        end)
    }

    HTTP.post(client, "/v3/Payments/FPS", body)
  end

  # ---

  defp build_single_body(payment) do
    %{
      "accountId" => Map.fetch!(payment, :account_id),
      "payments" => [build_payment_entry(payment)]
    }
  end

  defp build_payment_entry(p) do
    base = %{
      "amount" => Map.fetch!(p, :amount),
      "currencyCode" => Map.get(p, :currency, "GBP"),
      "destination" => %{
        "sortCode" => Map.fetch!(p, :destination_sort_code),
        "accountNumber" => Map.fetch!(p, :destination_account_number),
        "name" => Map.fetch!(p, :destination_account_name)
      },
      "paymentType" => payment_type_string(Map.get(p, :payment_type, :sip)),
      "enforceSendToScheme" => Map.get(p, :enforce_send_to_scheme, false)
    }

    base
    |> put_maybe("reference", Map.get(p, :reference))
    |> put_maybe("endToEndId", Map.get(p, :end_to_end_id))
  end

  defp payment_type_string(:sip), do: "SIP"
  defp payment_type_string(:sop), do: "SOP"
  defp payment_type_string(:fdp), do: "FDP"
  defp payment_type_string(s) when is_binary(s), do: s

  defp put_maybe(map, _key, nil), do: map
  defp put_maybe(map, key, value), do: Map.put(map, key, value)
end
