defmodule ClearBank.EmbeddedBanking.Accounts do
  @moduledoc """
  Embedded Banking account management — hub, payment, and savings accounts
  for your embedded customers.

  ## Account types

  - **Hub accounts** — internal pooled accounts you use to aggregate and manage funds
  - **Payment accounts** — FSCS-protected current/payment accounts for end customers
  - **Savings accounts** — interest-bearing accounts for end customers

  ## Examples

      # Create a payment account for a retail customer
      {:ok, acct} = ClearBank.EmbeddedBanking.Accounts.create_payment_account(client, %{
        customer_id: "cust-uuid",
        account_name: "Alice's Current Account"
      })

      # Create a savings account
      {:ok, savings} = ClearBank.EmbeddedBanking.Accounts.create_savings_account(client, %{
        customer_id: "cust-uuid",
        account_name: "Alice's Savings"
      })
  """

  alias ClearBank.{Client, HTTP, Types}

  @doc """
  Creates a hub account (internal pooled operational account).

  ## Required params

    * `:account_name` - display name for the hub account

  ## Optional params

    * `:owner` - your internal owner reference
    * `:currency` - ISO 4217 (default: `"GBP"`)
  """
  @spec create_hub_account(Client.t(), map()) :: HTTP.result()
  def create_hub_account(%Client{} = client, params) when is_map(params) do
    body =
      %{
        "accountName" => Map.fetch!(params, :account_name),
        "currency" => Map.get(params, :currency, "GBP")
      }
      |> put_maybe("owner", Map.get(params, :owner))

    HTTP.post(client, "/v1/fin/accounts/hub", body)
  end

  @doc """
  Creates a payment account for an embedded customer.

  ## Required params

    * `:customer_id` - UUID of the customer (retail, sole trader, or legal entity)
    * `:account_name` - display name

  ## Optional params

    * `:currency` - ISO 4217 (default: `"GBP"`)
    * `:external_account_id` - your internal account reference
  """
  @spec create_payment_account(Client.t(), map()) :: HTTP.result()
  def create_payment_account(%Client{} = client, params) when is_map(params) do
    body =
      %{
        "customerId" => Map.fetch!(params, :customer_id),
        "accountName" => Map.fetch!(params, :account_name),
        "currency" => Map.get(params, :currency, "GBP")
      }
      |> put_maybe("externalAccountId", Map.get(params, :external_account_id))

    HTTP.post(client, "/v1/fin/accounts/payment", body)
  end

  @doc """
  Creates a savings account for an embedded customer.

  ## Required params

    * `:customer_id` - UUID of the customer
    * `:account_name` - display name

  ## Optional params

    * `:currency` - ISO 4217 (default: `"GBP"`)
    * `:product_id` - interest product ID (from `ClearBank.EmbeddedBanking.Interest.list_products/1`)
    * `:external_account_id` - your internal reference
  """
  @spec create_savings_account(Client.t(), map()) :: HTTP.result()
  def create_savings_account(%Client{} = client, params) when is_map(params) do
    body =
      %{
        "customerId" => Map.fetch!(params, :customer_id),
        "accountName" => Map.fetch!(params, :account_name),
        "currency" => Map.get(params, :currency, "GBP")
      }
      |> put_maybe("productId", Map.get(params, :product_id))
      |> put_maybe("externalAccountId", Map.get(params, :external_account_id))

    HTTP.post(client, "/v1/fin/accounts/savings", body)
  end

  @doc """
  Returns all embedded accounts for a customer.

  ## Options

    * `:page_number`, `:page_size`
    * `:account_type` - filter by type: `"Payment"` | `"Savings"` | `"CashIsa"`

  ## Examples

      {:ok, accounts} = ClearBank.EmbeddedBanking.Accounts.list(client, "cust-uuid")
  """
  @spec list(Client.t(), String.t(), keyword()) :: HTTP.result()
  def list(%Client{} = client, customer_id, opts \\ []) when is_binary(customer_id) do
    params =
      opts
      |> Keyword.take([:page_number, :page_size, :account_type])
      |> Map.new()
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()

    HTTP.get(client, Types.build_path("/v1/fin/customers/#{customer_id}/accounts", params))
  end

  @doc """
  Returns an embedded account by ID.
  """
  @spec get(Client.t(), String.t()) :: HTTP.result()
  def get(%Client{} = client, account_id) when is_binary(account_id) do
    HTTP.get(client, "/v1/fin/accounts/#{account_id}")
  end

  @doc """
  Updates an embedded account (e.g. rename, change status).

  ## Optional params

    * `:account_name` - new display name
    * `:status` - `"Active"` | `"Suspended"` | `"Closed"`

  ## Examples

      {:ok, _} = ClearBank.EmbeddedBanking.Accounts.update(client, "acct-uuid",
        account_name: "Alice's Renamed Account"
      )
  """
  @spec update(Client.t(), String.t(), map()) :: HTTP.result()
  def update(%Client{} = client, account_id, params) when is_binary(account_id) do
    body =
      %{}
      |> put_maybe("accountName", Map.get(params, :account_name))
      |> put_maybe("status", Map.get(params, :status))

    HTTP.patch(client, "/v1/fin/accounts/#{account_id}", body)
  end

  @doc """
  Closes an embedded account.

  Sets account status to `"Closed"`. Ensure the balance is zero before closing.

  ## Examples

      {:ok, _} = ClearBank.EmbeddedBanking.Accounts.close(client, "acct-uuid")
  """
  @spec close(Client.t(), String.t()) :: HTTP.result()
  def close(%Client{} = client, account_id) when is_binary(account_id) do
    HTTP.patch(client, "/v1/fin/accounts/#{account_id}", %{"status" => "Closed"})
  end

  @doc """
  Returns all transactions for an embedded account.

  ## Options

    * `:page_number`, `:page_size`, `:start_date`, `:end_date`

  ## Examples

      {:ok, txns} = ClearBank.EmbeddedBanking.Accounts.list_transactions(client, "acct-uuid")
  """
  @spec list_transactions(Client.t(), String.t(), keyword()) :: HTTP.result()
  def list_transactions(%Client{} = client, account_id, opts \\ []) when is_binary(account_id) do
    params =
      opts
      |> Keyword.take([:page_number, :page_size, :start_date, :end_date])
      |> Map.new()
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()

    HTTP.get(client, Types.build_path("/v1/fin/accounts/#{account_id}/transactions", params))
  end

  @doc """
  Sends a Faster Payment from an embedded customer's payment account.

  This routes the payment through FPS on behalf of the embedded customer.
  CoP and APP scam rules apply.

  ## Required params

    * `:account_id` - embedded payment account UUID (source)
    * `:amount` - decimal string
    * `:currency` - `"GBP"`
    * `:destination_sort_code` - 6-digit sort code
    * `:destination_account_number` - 8-digit account number
    * `:destination_account_name` - payee name

  ## Optional params

    * `:reference` - payment reference (max 35 chars)
    * `:end_to_end_id` - your end-to-end reference

  ## Examples

      {:ok, _} = ClearBank.EmbeddedBanking.Accounts.send_payment(client, %{
        account_id: "embedded-acct-uuid",
        amount: "50.00",
        currency: "GBP",
        destination_sort_code: "040004",
        destination_account_number: "12345678",
        destination_account_name: "Bob",
        reference: "Rent"
      })
  """
  @spec send_payment(Client.t(), map()) :: HTTP.result()
  def send_payment(%Client{} = client, params) when is_map(params) do
    body =
      %{
        "amount" => Map.fetch!(params, :amount),
        "currencyCode" => Map.get(params, :currency, "GBP"),
        "destination" => %{
          "sortCode" => Map.fetch!(params, :destination_sort_code),
          "accountNumber" => Map.fetch!(params, :destination_account_number),
          "name" => Map.fetch!(params, :destination_account_name)
        }
      }
      |> put_maybe("reference", Map.get(params, :reference))
      |> put_maybe("endToEndId", Map.get(params, :end_to_end_id))

    HTTP.post(client, "/v1/fin/accounts/#{Map.fetch!(params, :account_id)}/payments/fps", body)
  end

  defp put_maybe(map, _key, nil), do: map
  defp put_maybe(map, key, value), do: Map.put(map, key, value)
end

defmodule ClearBank.EmbeddedBanking.Isa do
  @moduledoc """
  Flexible Cash ISA management for embedded retail customers.

  ## Key facts

  - ISA subscription limits are set by HMRC annually.
  - Flexible ISAs allow withdrawals and re-subscriptions within the same tax year.
  - ISA transfers-in must follow the HMRC ISA transfer process.

  ## Examples

      {:ok, isa} = ClearBank.EmbeddedBanking.Isa.create(client, %{
        customer_id: "cust-uuid",
        account_name: "Alice's Cash ISA"
      })

      {:ok, _} = ClearBank.EmbeddedBanking.Isa.transfer_in(client, "isa-acct-uuid", %{
        previous_provider_name: "Barclays",
        previous_provider_reference: "ISA123456",
        transfer_amount: "5000.00",
        transfer_type: "Cash"
      })
  """

  alias ClearBank.{Client, HTTP}

  @doc """
  Creates a Flexible Cash ISA account for a retail customer.

  ## Required params

    * `:customer_id` - UUID of the retail customer
    * `:account_name` - display name
  """
  @spec create(Client.t(), map()) :: HTTP.result()
  def create(%Client{} = client, params) when is_map(params) do
    body = %{
      "customerId" => Map.fetch!(params, :customer_id),
      "accountName" => Map.fetch!(params, :account_name)
    }

    HTTP.post(client, "/v1/fin/accounts/cash-isa", body)
  end

  @doc """
  Submits an ISA transfer-in request from a previous provider.

  ## Required params

    * `:previous_provider_name` - name of the previous ISA provider
    * `:previous_provider_reference` - ISA reference at the previous provider
    * `:transfer_amount` - decimal string amount to transfer
    * `:transfer_type` - `"Cash"` | `"InSpecie"`

  ## Optional params

    * `:previous_tax_year` - boolean, true if transferring previous years' ISA subscriptions
  """
  @spec transfer_in(Client.t(), String.t(), map()) :: HTTP.result()
  def transfer_in(%Client{} = client, account_id, params) when is_binary(account_id) do
    body = %{
      "previousProviderName" => Map.fetch!(params, :previous_provider_name),
      "previousProviderReference" => Map.fetch!(params, :previous_provider_reference),
      "transferAmount" => Map.fetch!(params, :transfer_amount),
      "transferType" => Map.fetch!(params, :transfer_type),
      "previousTaxYear" => Map.get(params, :previous_tax_year, false)
    }

    HTTP.put(client, "/v1/fin/accounts/cash-isa/#{account_id}/transfer-in", body)
  end
end

defmodule ClearBank.EmbeddedBanking.Interest do
  @moduledoc """
  Interest product configuration for embedded banking savings accounts.

  Configure which interest product applies to a savings account, and
  retrieve available products to display rates to your customers.

  ## Examples

      {:ok, products} = ClearBank.EmbeddedBanking.Interest.list_products(client)

      {:ok, _} = ClearBank.EmbeddedBanking.Interest.configure(client, "savings-acct-uuid", %{
        product_id: "prod-uuid"
      })
  """

  alias ClearBank.{Client, HTTP}

  @doc """
  Returns all available interest products configured for your institution.
  """
  @spec list_products(Client.t()) :: HTTP.result()
  def list_products(%Client{} = client) do
    HTTP.get(client, "/v1/fin/interest/products")
  end

  @doc """
  Configures an interest product for a savings account.

  ## Required params

    * `:product_id` - UUID of the interest product to apply
  """
  @spec configure(Client.t(), String.t(), map()) :: HTTP.result()
  def configure(%Client{} = client, account_id, params) when is_binary(account_id) do
    body = %{
      "productId" => Map.fetch!(params, :product_id)
    }

    HTTP.post(client, "/v1/fin/interest/accounts/#{account_id}", body)
  end
end

defmodule ClearBank.EmbeddedBanking.Kyc do
  @moduledoc """
  KYC (Know Your Customer) status management for embedded banking customers.

  ## KYC states

  - `"Pending"` — KYC not yet submitted
  - `"InProgress"` — KYC submitted, under review
  - `"Approved"` — customer passes KYC, can use financial products
  - `"Rejected"` — customer fails KYC
  - `"RequiresAction"` — additional documents or information required

  ## Webhooks

  ClearBank fires a `CustomerKycStatusChanged` webhook when KYC state transitions.
  Subscribe and handle this in `ClearBank.Webhook.Handler` to update your records.

  ## Examples

      {:ok, kyc} = ClearBank.EmbeddedBanking.Kyc.get_status(client, "cust-uuid")
      # => %{"status" => "Approved", "updatedAt" => "2024-01-15T10:00:00Z"}

      {:ok, _} = ClearBank.EmbeddedBanking.Kyc.submit(client, "cust-uuid", %{
        id_document_type: "Passport",
        id_document_number: "123456789",
        id_document_expiry: "2030-01-01",
        id_document_country: "GB"
      })
  """

  alias ClearBank.{Client, HTTP}

  @doc """
  Returns the current KYC status for a customer.
  """
  @spec get_status(Client.t(), String.t()) :: HTTP.result()
  def get_status(%Client{} = client, customer_id) when is_binary(customer_id) do
    HTTP.get(client, "/v1/fin/customers/#{customer_id}/kyc")
  end

  @doc """
  Submits or updates KYC data for a customer.

  ## Required params

    * `:id_document_type` - e.g. `"Passport"`, `"DrivingLicence"`, `"NationalId"`
    * `:id_document_number` - document number
    * `:id_document_expiry` - ISO 8601 date
    * `:id_document_country` - ISO 3166-1 alpha-2 issuing country

  ## Optional params

    * `:additional_documents` - list of additional document maps
    * `:source_of_funds` - e.g. `"Employment"`, `"Business"`, `"Savings"`
    * `:pep_status` - boolean, politically exposed person flag
    * `:sanctions_check` - boolean
  """
  @spec submit(Client.t(), String.t(), map()) :: HTTP.result()
  def submit(%Client{} = client, customer_id, params) when is_binary(customer_id) do
    body =
      %{
        "idDocumentType" => Map.fetch!(params, :id_document_type),
        "idDocumentNumber" => Map.fetch!(params, :id_document_number),
        "idDocumentExpiry" => Map.fetch!(params, :id_document_expiry),
        "idDocumentCountry" => Map.fetch!(params, :id_document_country)
      }
      |> put_maybe("sourceOfFunds", Map.get(params, :source_of_funds))
      |> put_maybe("pepStatus", Map.get(params, :pep_status))
      |> put_maybe("sanctionsCheck", Map.get(params, :sanctions_check))
      |> put_maybe("additionalDocuments", Map.get(params, :additional_documents))

    HTTP.put(client, "/v1/fin/customers/#{customer_id}/kyc", body)
  end

  defp put_maybe(map, _key, nil), do: map
  defp put_maybe(map, key, value), do: Map.put(map, key, value)
end
