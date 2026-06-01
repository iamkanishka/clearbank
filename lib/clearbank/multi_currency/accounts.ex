defmodule ClearBank.MultiCurrency.Accounts do
  @moduledoc """
  Multi-currency account management.

  On multi-currency onboarding, ClearBank provisions:
  - An **institution master account** — superset of all others
  - An **institution operating account**

  These are separate from your GBP accounts. You can create additional
  operational, safeguarded, and client money accounts, plus virtual accounts
  under general/segregated account types.

  ## Supported currencies

  Currency support depends on your agreement with ClearBank. Common currencies
  include EUR, USD, and others. Contact your ClearBank relationship manager.

  ## Examples

      {:ok, accounts} = ClearBank.MultiCurrency.Accounts.list(client)

      {:ok, account} = ClearBank.MultiCurrency.Accounts.create(client,
        account_name: "EUR Operating",
        account_type: :your_funds,
        currency: "EUR"
      )
  """

  alias ClearBank.{Client, HTTP, Types}

  @account_types %{
    your_funds: "YourFunds",
    safeguarded_pooled: "SafeguardedPooled",
    safeguarded_designated: "SafeguardedDesignated",
    client_money_pooled: "ClientMoneyPooled",
    client_money_designated: "ClientMoneyDesignated",
    segregated_pooled: "SegregatedPooled",
    segregated_designated: "SegregatedDesignated"
  }

  # ---- Real accounts ----

  @doc """
  Returns all multi-currency accounts.

  ## Options

    * `:page_number`, `:page_size`
    * `:currency` - filter by ISO 4217 currency code
  """
  @spec list(Client.t(), keyword()) :: HTTP.result()
  def list(%Client{} = client, opts \\ []) do
    params = opts |> Keyword.take([:page_number, :page_size, :currency]) |> Map.new()
    HTTP.get(client, Types.build_path("/mccy/v2/Accounts", params))
  end

  @doc """
  Returns a specific multi-currency account.
  """
  @spec get(Client.t(), String.t()) :: HTTP.result()
  def get(%Client{} = client, account_id) when is_binary(account_id) do
    HTTP.get(client, "/mccy/v2/Accounts/#{account_id}")
  end

  @doc """
  Creates a multi-currency real account.

  ## Required params

    * `:account_name` - display name
    * `:account_type` - account type atom (see module docs)
    * `:currency` - ISO 4217 code, e.g. `"EUR"`

  ## Optional params

    * `:owner` - owner reference
    * `:minimum_balance` - minimum balance enforcement
  """
  @spec create(Client.t(), keyword()) :: HTTP.result()
  def create(%Client{} = client, params) do
    type_str = @account_types |> Map.fetch!(Keyword.fetch!(params, :account_type))

    body =
      %{
        "accountName" => Keyword.fetch!(params, :account_name),
        "accountType" => type_str,
        "currencyCode" => Keyword.fetch!(params, :currency)
      }
      |> put_maybe("owner", Keyword.get(params, :owner))
      |> put_maybe("minimumBalance", Keyword.get(params, :minimum_balance))

    HTTP.post(client, "/mccy/v2/Accounts", body)
  end

  @doc """
  Amends a multi-currency account.
  """
  @spec update(Client.t(), String.t(), keyword()) :: HTTP.result()
  def update(%Client{} = client, account_id, params) do
    body =
      %{}
      |> put_maybe("accountName", Keyword.get(params, :account_name))
      |> put_maybe("copEnabled", Keyword.get(params, :cop_enabled))

    HTTP.patch(client, "/mccy/v2/Accounts/#{account_id}", body)
  end

  # ---- Virtual accounts ----

  @doc """
  Creates a virtual multi-currency account under a real account.

  ## Required params

    * `:account_name` - display name

  ## Optional params

    * `:owner` - owner reference string
  """
  @spec create_virtual(Client.t(), String.t(), keyword()) :: HTTP.result()
  def create_virtual(%Client{} = client, account_id, params) do
    body =
      %{"accountName" => Keyword.fetch!(params, :account_name)}
      |> put_maybe("owner", Keyword.get(params, :owner))

    HTTP.post(client, "/mccy/v2/Accounts/#{account_id}/Virtual", body)
  end

  @doc """
  Returns all virtual accounts under a multi-currency real account.
  """
  @spec list_virtual(Client.t(), String.t(), keyword()) :: HTTP.result()
  def list_virtual(%Client{} = client, account_id, opts \\ []) do
    params = opts |> Keyword.take([:page_number, :page_size]) |> Map.new()
    HTTP.get(client, Types.build_path("/mccy/v2/Accounts/#{account_id}/Virtual", params))
  end

  @doc """
  Returns a specific virtual multi-currency account.

  ## Examples

      {:ok, virtual} = ClearBank.MultiCurrency.Accounts.get_virtual(client, "acct-uuid", "virt-uuid")
  """
  @spec get_virtual(Client.t(), String.t(), String.t()) :: HTTP.result()
  def get_virtual(%Client{} = client, account_id, virtual_account_id)
      when is_binary(account_id) and is_binary(virtual_account_id) do
    HTTP.get(client, "/mccy/v2/Accounts/#{account_id}/Virtual/#{virtual_account_id}")
  end

  @doc """
  Amends a virtual multi-currency account.
  """
  @spec update_virtual(Client.t(), String.t(), String.t(), keyword()) :: HTTP.result()
  def update_virtual(%Client{} = client, account_id, virtual_account_id, params) do
    body = %{} |> put_maybe("accountName", Keyword.get(params, :account_name))
    HTTP.patch(client, "/mccy/v2/Accounts/#{account_id}/Virtual/#{virtual_account_id}", body)
  end

  # ---- Transactions ----

  @doc """
  Returns transactions for a multi-currency account.

  ## Options

    * `:page_number`, `:page_size`, `:start_date`, `:end_date`
  """
  @spec list_transactions(Client.t(), String.t(), keyword()) :: HTTP.result()
  def list_transactions(%Client{} = client, account_id, opts \\ []) do
    params =
      opts |> Keyword.take([:page_number, :page_size, :start_date, :end_date]) |> Map.new()

    HTTP.get(client, Types.build_path("/mccy/v2/Accounts/#{account_id}/Transactions", params))
  end

  defp put_maybe(map, _key, nil), do: map
  defp put_maybe(map, key, value), do: Map.put(map, key, value)
end
