defmodule ClearBank.Payments.InternalTransfer do
  @moduledoc """
  Internal Transfers — move funds between accounts held at ClearBank
  without going through an external payment scheme.

  ## Key facts

  - **No scheme fees** — transfers are between ClearBank-held accounts
  - **Not subject to APP scam reimbursement** — unlike FPS scheme routing
  - **Instant** — settlement is immediate within ClearBank's ledger
  - **No upper limit** — unlike FPS (£1m cap)

  ## When to use

  Use internal transfers when:
  - Moving funds between your own institution accounts (e.g. operational to segregated)
  - Sweeping from a hub account to a customer payment account (Embedded Banking)
  - Transferring between a real account and its virtual accounts

  ## vs Faster Payments

  When the destination is a ClearBank client and `enforce_send_to_scheme: false` (default),
  FPS payments are automatically routed as internal transfers. Use this module when
  you want **explicit** internal transfer semantics and the transfer stays within ClearBank.

  ## Examples

      {:ok, result} = ClearBank.Payments.InternalTransfer.send(client, %{
        debtor_account_id: "source-acct-uuid",
        creditor_account_id: "dest-acct-uuid",
        amount: "5000.00",
        currency: "GBP",
        reference: "Sweep to segregated"
      })
  """

  alias ClearBank.{Client, HTTP}

  @doc """
  Sends an internal transfer between two ClearBank accounts.

  ## Required params

    * `:debtor_account_id` - source account UUID
    * `:creditor_account_id` - destination account UUID
    * `:amount` - decimal string amount
    * `:currency` - ISO 4217 code (default: `"GBP"`)

  ## Optional params

    * `:reference` - transfer reference (max 35 chars)
    * `:end_to_end_id` - your end-to-end reference for idempotency tracking
    * `:debtor_virtual_account_id` - if debiting a virtual account
    * `:creditor_virtual_account_id` - if crediting a virtual account

  ## Examples

      # Between two real accounts
      {:ok, _} = ClearBank.Payments.InternalTransfer.send(client, %{
        debtor_account_id: "ops-acct-uuid",
        creditor_account_id: "segregated-acct-uuid",
        amount: "10000.00",
        currency: "GBP",
        reference: "Daily sweep"
      })

      # From a real account to a virtual account
      {:ok, _} = ClearBank.Payments.InternalTransfer.send(client, %{
        debtor_account_id: "hub-acct-uuid",
        creditor_account_id: "pool-acct-uuid",
        creditor_virtual_account_id: "customer-virt-uuid",
        amount: "250.00",
        currency: "GBP",
        reference: "Customer top-up"
      })
  """
  @spec send(Client.t(), map()) :: HTTP.result()
  def send(%Client{} = client, params) when is_map(params) do
    body =
      %{
        "debtorAccountId" => Map.fetch!(params, :debtor_account_id),
        "creditorAccountId" => Map.fetch!(params, :creditor_account_id),
        "amount" => Map.fetch!(params, :amount),
        "currencyCode" => Map.get(params, :currency, "GBP")
      }
      |> put_maybe("reference", Map.get(params, :reference))
      |> put_maybe("endToEndId", Map.get(params, :end_to_end_id))
      |> put_maybe("debtorVirtualAccountId", Map.get(params, :debtor_virtual_account_id))
      |> put_maybe("creditorVirtualAccountId", Map.get(params, :creditor_virtual_account_id))

    HTTP.post(client, "/v3/Payments/Transfer", body)
  end

  @doc """
  Sends multiple internal transfers in a single request (bulk).

  ## Params

    * `transfers` - list of transfer maps (same fields as `send/2`)

  ## Examples

      {:ok, _} = ClearBank.Payments.InternalTransfer.send_bulk(client, [
        %{debtor_account_id: "acct-1", creditor_account_id: "acct-2",
          amount: "100.00", currency: "GBP"},
        %{debtor_account_id: "acct-1", creditor_account_id: "acct-3",
          amount: "200.00", currency: "GBP"}
      ])
  """
  @spec send_bulk(Client.t(), [map()]) :: HTTP.result()
  def send_bulk(%Client{} = client, transfers) when is_list(transfers) do
    body = %{
      "transfers" =>
        Enum.map(transfers, fn t ->
          %{
            "debtorAccountId" => Map.fetch!(t, :debtor_account_id),
            "creditorAccountId" => Map.fetch!(t, :creditor_account_id),
            "amount" => Map.fetch!(t, :amount),
            "currencyCode" => Map.get(t, :currency, "GBP")
          }
          |> put_maybe("reference", Map.get(t, :reference))
          |> put_maybe("endToEndId", Map.get(t, :end_to_end_id))
          |> put_maybe("debtorVirtualAccountId", Map.get(t, :debtor_virtual_account_id))
          |> put_maybe("creditorVirtualAccountId", Map.get(t, :creditor_virtual_account_id))
        end)
    }

    HTTP.post(client, "/v3/Payments/Transfer/Bulk", body)
  end

  defp put_maybe(map, _key, nil), do: map
  defp put_maybe(map, key, value), do: Map.put(map, key, value)
end
