defmodule ClearBank.EmbeddedBanking.Customers do
  @moduledoc """
  Embedded Banking customer management — onboard retail, sole trader,
  and legal entity customers onto your platform, backed by ClearBank.

  ## Customer types

  - **Retail** — individual consumers (personal accounts)
  - **Sole Trader** — self-employed individuals trading under their own name
  - **Legal Entity** — companies, LLPs, partnerships, and other incorporated entities

  ## KYC

  Customer records are separate from KYC status. After creating a customer,
  use `ClearBank.EmbeddedBanking.Kyc` to submit and query KYC data.

  ## Examples

      # Create a retail customer
      {:ok, customer} = ClearBank.EmbeddedBanking.Customers.create_retail(client, %{
        first_name: "Alice",
        last_name: "Smith",
        date_of_birth: "1990-05-15",
        email: "alice@example.com",
        phone: "+447700900000"
      })

      # Create a legal entity
      {:ok, entity} = ClearBank.EmbeddedBanking.Customers.create_legal_entity(client, %{
        company_name: "ACME Ltd",
        registration_number: "12345678",
        registered_country: "GB",
        company_type: "PrivateLimitedCompany"
      })
  """

  alias ClearBank.{Client, HTTP, Types}

  # ---- List ----

  @doc """
  Returns all customers for your institution.

  ## Options

    * `:page_number`, `:page_size`
    * `:customer_type` - filter: `"Retail"` | `"SoleTrader"` | `"LegalEntity"`
    * `:external_customer_id` - filter by your own reference

  ## Examples

      {:ok, customers} = ClearBank.EmbeddedBanking.Customers.list(client)
      {:ok, customers} = ClearBank.EmbeddedBanking.Customers.list(client, customer_type: "Retail")
  """
  @spec list(Client.t(), keyword()) :: HTTP.result()
  def list(%Client{} = client, opts \\ []) do
    params =
      opts
      |> Keyword.take([:page_number, :page_size, :customer_type, :external_customer_id])
      |> Map.new()
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()

    HTTP.get(client, Types.build_path("/v1/fin/customers", params))
  end

  # ---- Retail ----

  @doc """
  Creates a retail (individual consumer) customer.

  ## Required params

    * `:first_name`
    * `:last_name`
    * `:date_of_birth` - ISO 8601 date string, e.g. `"1990-05-15"`

  ## Optional params

    * `:email` - contact email
    * `:phone` - E.164 phone number
    * `:external_customer_id` - your internal customer reference
    * `:address` - map with `:line1`, `:line2`, `:city`, `:post_code`, `:country`
    * `:nationality` - ISO 3166-1 alpha-2 country code
    * `:tax_country` - ISO 3166-1 alpha-2 tax residency country
  """
  @spec create_retail(Client.t(), map()) :: HTTP.result()
  def create_retail(%Client{} = client, params) when is_map(params) do
    body = build_retail_body(params)
    HTTP.post(client, "/v1/fin/customers/retail", body)
  end

  @doc """
  Returns a customer by ID (any type).

  ## Examples

      {:ok, customer} = ClearBank.EmbeddedBanking.Customers.get(client, "cust-uuid")
  """
  @spec get(Client.t(), String.t()) :: HTTP.result()
  def get(%Client{} = client, customer_id) when is_binary(customer_id) do
    HTTP.get(client, "/v1/fin/customers/#{customer_id}")
  end

  @doc """
  Updates a customer record.

  ## Examples

      {:ok, _} = ClearBank.EmbeddedBanking.Customers.update(client, "cust-uuid", %{
        email: "newemail@example.com"
      })
  """
  @spec update(Client.t(), String.t(), map()) :: HTTP.result()
  def update(%Client{} = client, customer_id, params) when is_binary(customer_id) do
    body = build_update_body(params)
    HTTP.patch(client, "/v1/fin/customers/#{customer_id}", body)
  end

  # ---- Sole Trader ----

  @doc """
  Creates a sole trader customer.

  ## Required params

    * `:first_name`, `:last_name`, `:date_of_birth`
    * `:trading_name` - business trading name

  ## Optional params

    * `:email`, `:phone`, `:external_customer_id`
    * `:business_address` - trading address map
    * `:utr` - Unique Taxpayer Reference
  """
  @spec create_sole_trader(Client.t(), map()) :: HTTP.result()
  def create_sole_trader(%Client{} = client, params) when is_map(params) do
    body =
      %{
        "firstName" => Map.fetch!(params, :first_name),
        "lastName" => Map.fetch!(params, :last_name),
        "dateOfBirth" => Map.fetch!(params, :date_of_birth),
        "tradingName" => Map.fetch!(params, :trading_name)
      }
      |> put_maybe("email", Map.get(params, :email))
      |> put_maybe("phone", Map.get(params, :phone))
      |> put_maybe("externalCustomerId", Map.get(params, :external_customer_id))
      |> put_maybe("utr", Map.get(params, :utr))
      |> put_maybe("businessAddress", build_address(Map.get(params, :business_address)))

    HTTP.post(client, "/v2/fin/customers/sole-traders", body)
  end

  @doc """
  Updates a sole trader customer.

  ## Optional params

    * `:email`, `:phone`
    * `:business_address` - trading address map

  ## Examples

      {:ok, _} = ClearBank.EmbeddedBanking.Customers.update_sole_trader(client, "cust-uuid", %{
        email: "newemail@example.com"
      })
  """
  @spec update_sole_trader(Client.t(), String.t(), map()) :: HTTP.result()
  def update_sole_trader(%Client{} = client, customer_id, params) when is_binary(customer_id) do
    body = build_update_body(params)
    HTTP.patch(client, "/v2/fin/customers/sole-traders/#{customer_id}", body)
  end

  # ---- Legal Entity ----

  @doc """
  Creates a legal entity (company, LLP, etc.) customer.

  ## Required params

    * `:company_name` - registered company name
    * `:registration_number` - companies house / equivalent registration number
    * `:registered_country` - ISO 3166-1 alpha-2, e.g. `"GB"`
    * `:company_type` - e.g. `"PrivateLimitedCompany"`, `"PublicLimitedCompany"`, `"LLP"`

  ## Optional params

    * `:email`, `:phone`, `:external_customer_id`
    * `:registered_address` - address map
    * `:trading_address` - address map
    * `:sic_code` - Standard Industrial Classification code
    * `:vat_number`
    * `:beneficial_owners` - list of beneficial owner maps
  """
  @spec create_legal_entity(Client.t(), map()) :: HTTP.result()
  def create_legal_entity(%Client{} = client, params) when is_map(params) do
    body =
      %{
        "companyName" => Map.fetch!(params, :company_name),
        "registrationNumber" => Map.fetch!(params, :registration_number),
        "registeredCountry" => Map.fetch!(params, :registered_country),
        "companyType" => Map.fetch!(params, :company_type)
      }
      |> put_maybe("email", Map.get(params, :email))
      |> put_maybe("phone", Map.get(params, :phone))
      |> put_maybe("externalCustomerId", Map.get(params, :external_customer_id))
      |> put_maybe("sicCode", Map.get(params, :sic_code))
      |> put_maybe("vatNumber", Map.get(params, :vat_number))
      |> put_maybe("registeredAddress", build_address(Map.get(params, :registered_address)))
      |> put_maybe("tradingAddress", build_address(Map.get(params, :trading_address)))
      |> put_maybe(
        "beneficialOwners",
        build_beneficial_owners(Map.get(params, :beneficial_owners))
      )

    HTTP.post(client, "/v2/fin/customers/legal-entities", body)
  end

  @doc """
  Updates a legal entity customer.
  """
  @spec update_legal_entity(Client.t(), String.t(), map()) :: HTTP.result()
  def update_legal_entity(%Client{} = client, customer_id, params) when is_binary(customer_id) do
    body = build_update_body(params)
    HTTP.patch(client, "/v2/fin/customers/legal-entities/#{customer_id}", body)
  end

  # --- Helpers ---

  defp build_retail_body(params) do
    %{
      "firstName" => Map.fetch!(params, :first_name),
      "lastName" => Map.fetch!(params, :last_name),
      "dateOfBirth" => Map.fetch!(params, :date_of_birth)
    }
    |> put_maybe("email", Map.get(params, :email))
    |> put_maybe("phone", Map.get(params, :phone))
    |> put_maybe("externalCustomerId", Map.get(params, :external_customer_id))
    |> put_maybe("nationality", Map.get(params, :nationality))
    |> put_maybe("taxCountry", Map.get(params, :tax_country))
    |> put_maybe("address", build_address(Map.get(params, :address)))
  end

  defp build_update_body(params) do
    %{}
    |> put_maybe("email", Map.get(params, :email))
    |> put_maybe("phone", Map.get(params, :phone))
    |> put_maybe("address", build_address(Map.get(params, :address)))
  end

  defp build_address(nil), do: nil

  defp build_address(addr) do
    %{
      "addressLine1" => Map.get(addr, :line1),
      "addressLine2" => Map.get(addr, :line2),
      "city" => Map.get(addr, :city),
      "postCode" => Map.get(addr, :post_code),
      "country" => Map.get(addr, :country)
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp build_beneficial_owners(nil), do: nil

  defp build_beneficial_owners(owners) when is_list(owners) do
    Enum.map(owners, fn o ->
      %{
        "firstName" => Map.get(o, :first_name),
        "lastName" => Map.get(o, :last_name),
        "dateOfBirth" => Map.get(o, :date_of_birth),
        "ownershipPercentage" => Map.get(o, :ownership_percentage)
      }
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()
    end)
  end

  defp put_maybe(map, _key, nil), do: map
  defp put_maybe(map, key, value), do: Map.put(map, key, value)
end
