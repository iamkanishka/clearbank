defmodule ClearBank.Accounts do
  @moduledoc """
  GBP Account management — real and virtual accounts.

  ## Real accounts

  When you join ClearBank, four accounts are provisioned automatically:
  - Operational Account
  - General Segregation Account
  - Bacs Suspense Account
  - Mandated Minimum Balance Account

  You can create additional real accounts of most types via `create/2`.

  ## Virtual accounts

  Virtual accounts exist on your platform; their funds sit in a parent real account
  at ClearBank. You are responsible for reconciliation. Each has a virtual IBAN (vIBAN).

  ## Account types

  | Atom | API value | Purpose |
  |---|---|---|
  | `:your_funds` | `YourFunds` | Operational: your own institution funds |
  | `:client_money_pooled` | `ClientMoneyPooled` | CASS 7 pooled client money |
  | `:client_money_designated` | `ClientMoneyDesignated` | CASS 7 designated per client |
  | `:segregated_pooled` | `SegregatedPooled` | Pooled customer funds |
  | `:segregated_designated` | `SegregatedDesignated` | Designated per customer |
  | `:safeguarded_pooled` | `SafeguardedPooled` | FCA CASS 15 safeguarding |
  | `:safeguarded_designated` | `SafeguardedDesignated` | CASS 15 designated |
  | `:client_suspense` | `ClientSuspense` | Embedded Banking partners only |

  > **Note:** From 7 May 2026, all FCA-regulated payment/e-money institutions must
  > hold at least one safeguarded account. Submit a CASS 15-compliant letter to
  > ClearBank annually.
  """

  alias ClearBank.{Client, HTTP, Types}

  @account_types %{
    your_funds: "YourFunds",
    client_money_pooled: "ClientMoneyPooled",
    client_money_designated: "ClientMoneyDesignated",
    segregated_pooled: "SegregatedPooled",
    segregated_designated: "SegregatedDesignated",
    safeguarded_pooled: "SafeguardedPooled",
    safeguarded_designated: "SafeguardedDesignated",
    client_suspense: "ClientSuspense"
  }

  @type account_type ::
          :your_funds
          | :client_money_pooled
          | :client_money_designated
          | :segregated_pooled
          | :segregated_designated
          | :safeguarded_pooled
          | :safeguarded_designated
          | :client_suspense

  # ---- Real Accounts ----

  @doc """
  Returns all real GBP accounts for your institution.

  ## Options

    * `:page_number` - page (default: 1)
    * `:page_size` - results per page (default: 50)

  ## Examples

      {:ok, accounts} = ClearBank.Accounts.list(client)
      {:ok, accounts} = ClearBank.Accounts.list(client, page_number: 1, page_size: 20)
  """
  @spec list(Client.t(), keyword()) :: HTTP.result()
  def list(%Client{} = client, opts \\ []) do
    params = Map.new(opts) |> Map.take([:page_number, :page_size])
    HTTP.get(client, Types.build_path("/v3/Accounts", params))
  end

  @doc """
  Returns a single real GBP account by ID.

  ## Examples

      {:ok, account} = ClearBank.Accounts.get(client, "acct-uuid")
  """
  @spec get(Client.t(), String.t()) :: HTTP.result()
  def get(%Client{} = client, account_id) when is_binary(account_id) do
    HTTP.get(client, "/v3/Accounts/#{account_id}")
  end

  @doc """
  Creates a new real GBP account.

  ## Required params

    * `:account_name` - display name for the account
    * `:account_type` - one of the account type atoms above

  ## Optional params

    * `:sort_code` - override sort code (if permitted)
    * `:usage_type` - `:payments` | `:savings`
    * `:minimum_balance` - minimum balance enforcement

  ## Examples

      {:ok, account} = ClearBank.Accounts.create(client,
        account_name: "Client Pool GBP",
        account_type: :segregated_pooled
      )
  """
  @spec create(Client.t(), keyword()) :: HTTP.result()
  def create(%Client{} = client, params) do
    body = build_account_body(params)
    HTTP.post(client, "/v3/Accounts", body)
  end

  @doc """
  Amends a real GBP account (e.g. rename, enable/disable CoP).

  ## Examples

      {:ok, _} = ClearBank.Accounts.update(client, "acct-uuid",
        account_name: "New Name"
      )
  """
  @spec update(Client.t(), String.t(), keyword()) :: HTTP.result()
  def update(%Client{} = client, account_id, params) when is_binary(account_id) do
    body = build_update_body(params)
    HTTP.patch(client, "/v1/Accounts/#{account_id}", body)
  end

  # ---- Virtual Accounts ----

  @doc """
  Returns all virtual accounts under a real account.

  ## Examples

      {:ok, virtuals} = ClearBank.Accounts.list_virtual(client, "acct-uuid")
  """
  @spec list_virtual(Client.t(), String.t(), keyword()) :: HTTP.result()
  def list_virtual(%Client{} = client, account_id, opts \\ []) do
    params = Map.new(opts) |> Map.take([:page_number, :page_size])
    HTTP.get(client, Types.build_path("/v2/Accounts/#{account_id}/Virtual", params))
  end

  @doc """
  Returns a specific virtual account.

  ## Examples

      {:ok, virtual} = ClearBank.Accounts.get_virtual(client, "acct-uuid", "virt-uuid")
  """
  @spec get_virtual(Client.t(), String.t(), String.t()) :: HTTP.result()
  def get_virtual(%Client{} = client, account_id, virtual_account_id) do
    HTTP.get(client, "/v2/Accounts/#{account_id}/Virtual/#{virtual_account_id}")
  end

  @doc """
  Creates a new virtual account under a real account.

  ## Required params

    * `:account_name` - display name

  ## Optional params

    * `:owner` - owner reference string (for your records)
    * `:sort_code` - override sort code if permitted

  ## Examples

      {:ok, virtual} = ClearBank.Accounts.create_virtual(client, "acct-uuid",
        account_name: "Customer ABC Virtual"
      )
  """
  @spec create_virtual(Client.t(), String.t(), keyword()) :: HTTP.result()
  def create_virtual(%Client{} = client, account_id, params) when is_binary(account_id) do
    body = build_account_body(params)
    HTTP.post(client, "/v2/Accounts/#{account_id}/Virtual", body)
  end

  @doc """
  Amends a virtual account.

  ## Examples

      {:ok, _} = ClearBank.Accounts.update_virtual(client, "acct-uuid", "virt-uuid",
        account_name: "Updated Name"
      )
  """
  @spec update_virtual(Client.t(), String.t(), String.t(), keyword()) :: HTTP.result()
  def update_virtual(%Client{} = client, account_id, virtual_account_id, params) do
    body = build_update_body(params)
    HTTP.patch(client, "/v1/Accounts/#{account_id}/Virtual/#{virtual_account_id}", body)
  end

  # ---- Private helpers ----

  defp build_account_body(params) do
    type_atom = Keyword.get(params, :account_type)
    type_str = if type_atom, do: Map.fetch!(@account_types, type_atom), else: nil

    %{}
    |> put_if(Keyword.get(params, :account_name), "accountName")
    |> put_if(type_str, "accountType")
    |> put_if(Keyword.get(params, :owner), "owner")
    |> put_if(Keyword.get(params, :sort_code), "sortCode")
    |> put_if(Keyword.get(params, :usage_type), "usageType")
    |> put_if(Keyword.get(params, :minimum_balance), "minimumBalance")
  end

  defp build_update_body(params) do
    %{}
    |> put_if(Keyword.get(params, :account_name), "accountName")
    |> put_if(Keyword.get(params, :cop_enabled), "copEnabled")
  end

  defp put_if(map, nil, _key), do: map
  defp put_if(map, value, key), do: Map.put(map, key, value)
end
