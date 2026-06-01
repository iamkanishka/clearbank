defmodule ClearBank.Schemas do
  @moduledoc """
  Typed response structs for ClearBank API responses.

  All API functions return raw maps by default (matching the JSON response body).
  Use these structs when you want typed, structured access to response data
  with atom keys and helper functions.

  ## Usage

      {:ok, body} = ClearBank.Accounts.get(client, account_id)
      account = ClearBank.Schemas.Account.from_map(body)

      account.id          # => "acct-uuid-1"
      account.name        # => "My Account"
      account.type        # => :segregated_pooled
      account.balance     # => "10000.00"
  """

  defmodule Account do
    @moduledoc "Typed struct for a GBP real account."

    @type account_type ::
            :your_funds
            | :client_money_pooled
            | :client_money_designated
            | :segregated_pooled
            | :segregated_designated
            | :safeguarded_pooled
            | :safeguarded_designated
            | :client_suspense

    @type status :: :active | :suspended | :closed

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t(),
            type: account_type(),
            status: status(),
            iban: String.t() | nil,
            sort_code: String.t() | nil,
            account_number: String.t() | nil,
            currency: String.t(),
            balance: String.t() | nil,
            available_balance: String.t() | nil,
            cop_enabled: boolean(),
            created_at: String.t() | nil
          }

    defstruct [
      :id,
      :name,
      :type,
      :status,
      :iban,
      :sort_code,
      :account_number,
      :currency,
      :balance,
      :available_balance,
      :created_at,
      cop_enabled: false
    ]

    @spec from_map(map()) :: t()
    def from_map(m) when is_map(m) do
      %__MODULE__{
        id: m["id"] || m["accountId"],
        name: m["name"] || m["accountName"],
        type: parse_type(m["type"] || m["accountType"]),
        status: parse_status(m["status"]),
        iban: m["iban"],
        sort_code: m["sortCode"],
        account_number: m["accountNumber"],
        currency: m["currency"] || m["currencyCode"] || "GBP",
        balance: m["balance"],
        available_balance: m["availableBalance"],
        cop_enabled: m["copEnabled"] || false,
        created_at: m["createdAt"]
      }
    end

    defp parse_type("YourFunds"), do: :your_funds
    defp parse_type("ClientMoneyPooled"), do: :client_money_pooled
    defp parse_type("ClientMoneyDesignated"), do: :client_money_designated
    defp parse_type("SegregatedPooled"), do: :segregated_pooled
    defp parse_type("SegregatedDesignated"), do: :segregated_designated
    defp parse_type("SafeguardedPooled"), do: :safeguarded_pooled
    defp parse_type("SafeguardedDesignated"), do: :safeguarded_designated
    defp parse_type("ClientSuspense"), do: :client_suspense
    defp parse_type(_), do: nil

    defp parse_status("Active"), do: :active
    defp parse_status("Suspended"), do: :suspended
    defp parse_status("Closed"), do: :closed
    defp parse_status(_), do: nil
  end

  defmodule VirtualAccount do
    @moduledoc "Typed struct for a GBP virtual account."

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t(),
            iban: String.t() | nil,
            sort_code: String.t() | nil,
            account_number: String.t() | nil,
            status: String.t() | nil,
            owner: String.t() | nil,
            created_at: String.t() | nil
          }

    defstruct [:id, :name, :iban, :sort_code, :account_number, :status, :owner, :created_at]

    @spec from_map(map()) :: t()
    def from_map(m) when is_map(m) do
      %__MODULE__{
        id: m["id"] || m["virtualAccountId"],
        name: m["name"] || m["accountName"],
        iban: m["iban"],
        sort_code: m["sortCode"],
        account_number: m["accountNumber"],
        status: m["status"],
        owner: m["owner"],
        created_at: m["createdAt"]
      }
    end
  end

  defmodule Transaction do
    @moduledoc "Typed struct for a GBP account transaction."

    @type direction :: :inbound | :outbound
    @type status :: :settled | :pending | :rejected | :returned

    @type t :: %__MODULE__{
            id: String.t(),
            account_id: String.t(),
            virtual_account_id: String.t() | nil,
            amount: String.t(),
            currency: String.t(),
            direction: direction(),
            type: String.t(),
            status: status(),
            reference: String.t() | nil,
            counterpart_name: String.t() | nil,
            counterpart_sort_code: String.t() | nil,
            counterpart_account_number: String.t() | nil,
            end_to_end_id: String.t() | nil,
            created_at: String.t() | nil
          }

    defstruct [
      :id,
      :account_id,
      :virtual_account_id,
      :amount,
      :currency,
      :direction,
      :type,
      :status,
      :reference,
      :counterpart_name,
      :counterpart_sort_code,
      :counterpart_account_number,
      :end_to_end_id,
      :created_at
    ]

    @spec from_map(map()) :: t()
    def from_map(m) when is_map(m) do
      %__MODULE__{
        id: m["id"] || m["transactionId"],
        account_id: m["accountId"],
        virtual_account_id: m["virtualAccountId"],
        amount: m["amount"],
        currency: m["currency"] || m["currencyCode"] || "GBP",
        direction: parse_direction(m["direction"]),
        type: m["type"],
        status: parse_status(m["status"]),
        reference: m["reference"],
        counterpart_name: m["counterpartName"],
        counterpart_sort_code: m["counterpartSortCode"],
        counterpart_account_number: m["counterpartAccountNumber"],
        end_to_end_id: m["endToEndId"],
        created_at: m["createdAt"] || m["timestamp"]
      }
    end

    defp parse_direction("Inbound"), do: :inbound
    defp parse_direction("Outbound"), do: :outbound
    defp parse_direction(_), do: nil

    defp parse_status("Settled"), do: :settled
    defp parse_status("Pending"), do: :pending
    defp parse_status("Rejected"), do: :rejected
    defp parse_status("Returned"), do: :returned
    defp parse_status(_), do: nil
  end

  defmodule DirectDebitInstruction do
    @moduledoc "Typed struct for a Bacs Direct Debit Instruction (DDI/mandate)."

    @type t :: %__MODULE__{
            id: String.t(),
            account_id: String.t(),
            service_user_number: String.t(),
            reference: String.t(),
            payer_name: String.t(),
            payer_sort_code: String.t(),
            payer_account_number: String.t(),
            status: String.t() | nil,
            created_at: String.t() | nil
          }

    defstruct [
      :id,
      :account_id,
      :service_user_number,
      :reference,
      :payer_name,
      :payer_sort_code,
      :payer_account_number,
      :status,
      :created_at
    ]

    @spec from_map(map()) :: t()
    def from_map(m) when is_map(m) do
      payer = m["payerDetails"] || %{}

      %__MODULE__{
        id: m["id"] || m["mandateId"],
        account_id: m["accountId"],
        service_user_number: m["serviceUserNumber"],
        reference: m["reference"],
        payer_name: payer["name"],
        payer_sort_code: payer["sortCode"],
        payer_account_number: payer["accountNumber"],
        status: m["status"],
        created_at: m["createdAt"]
      }
    end
  end

  defmodule Customer do
    @moduledoc "Typed struct for an Embedded Banking customer."

    @type customer_type :: :retail | :sole_trader | :legal_entity
    @type kyc_status :: :pending | :in_progress | :approved | :rejected | :requires_action

    @type t :: %__MODULE__{
            id: String.t(),
            type: customer_type(),
            first_name: String.t() | nil,
            last_name: String.t() | nil,
            company_name: String.t() | nil,
            email: String.t() | nil,
            phone: String.t() | nil,
            kyc_status: kyc_status() | nil,
            external_customer_id: String.t() | nil,
            created_at: String.t() | nil
          }

    defstruct [
      :id,
      :type,
      :first_name,
      :last_name,
      :company_name,
      :email,
      :phone,
      :kyc_status,
      :external_customer_id,
      :created_at
    ]

    @spec from_map(map()) :: t()
    def from_map(m) when is_map(m) do
      %__MODULE__{
        id: m["customerId"] || m["id"],
        type: parse_type(m["customerType"] || m["type"]),
        first_name: m["firstName"],
        last_name: m["lastName"],
        company_name: m["companyName"],
        email: m["email"],
        phone: m["phone"],
        kyc_status: parse_kyc_status(m["kycStatus"]),
        external_customer_id: m["externalCustomerId"],
        created_at: m["createdAt"]
      }
    end

    defp parse_type("Retail"), do: :retail
    defp parse_type("SoleTrader"), do: :sole_trader
    defp parse_type("LegalEntity"), do: :legal_entity
    defp parse_type(_), do: nil

    defp parse_kyc_status("Pending"), do: :pending
    defp parse_kyc_status("InProgress"), do: :in_progress
    defp parse_kyc_status("Approved"), do: :approved
    defp parse_kyc_status("Rejected"), do: :rejected
    defp parse_kyc_status("RequiresAction"), do: :requires_action
    defp parse_kyc_status(_), do: nil
  end

  defmodule EmbeddedAccount do
    @moduledoc "Typed struct for an Embedded Banking account."

    @type account_type :: :payment | :savings | :cash_isa | :hub
    @type status :: :active | :suspended | :closed

    @type t :: %__MODULE__{
            id: String.t(),
            customer_id: String.t() | nil,
            name: String.t(),
            type: account_type(),
            status: status(),
            iban: String.t() | nil,
            sort_code: String.t() | nil,
            account_number: String.t() | nil,
            currency: String.t(),
            balance: String.t() | nil,
            created_at: String.t() | nil
          }

    defstruct [
      :id,
      :customer_id,
      :name,
      :type,
      :status,
      :iban,
      :sort_code,
      :account_number,
      :currency,
      :balance,
      :created_at
    ]

    @spec from_map(map()) :: t()
    def from_map(m) when is_map(m) do
      %__MODULE__{
        id: m["accountId"] || m["id"],
        customer_id: m["customerId"],
        name: m["accountName"] || m["name"],
        type: parse_type(m["accountType"] || m["type"]),
        status: parse_status(m["status"]),
        iban: m["iban"],
        sort_code: m["sortCode"],
        account_number: m["accountNumber"],
        currency: m["currency"] || m["currencyCode"] || "GBP",
        balance: m["balance"],
        created_at: m["createdAt"]
      }
    end

    defp parse_type("Payment"), do: :payment
    defp parse_type("Savings"), do: :savings
    defp parse_type("CashIsa"), do: :cash_isa
    defp parse_type("Hub"), do: :hub
    defp parse_type(_), do: nil

    defp parse_status("Active"), do: :active
    defp parse_status("Suspended"), do: :suspended
    defp parse_status("Closed"), do: :closed
    defp parse_status(_), do: nil
  end

  defmodule FxQuote do
    @moduledoc "Typed struct for an FX RFQ quote."

    @type t :: %__MODULE__{
            quote_id: String.t(),
            sell_currency: String.t(),
            buy_currency: String.t(),
            sell_amount: String.t() | nil,
            buy_amount: String.t() | nil,
            rate: String.t(),
            expires_at: String.t()
          }

    defstruct [
      :quote_id,
      :sell_currency,
      :buy_currency,
      :sell_amount,
      :buy_amount,
      :rate,
      :expires_at
    ]

    @spec from_map(map()) :: t()
    def from_map(m) when is_map(m) do
      %__MODULE__{
        quote_id: m["quoteId"],
        sell_currency: m["sellCurrency"],
        buy_currency: m["buyCurrency"],
        sell_amount: m["sellAmount"],
        buy_amount: m["buyAmount"],
        rate: m["rate"],
        expires_at: m["expiresAt"]
      }
    end

    @doc "Returns true if the quote has expired."
    @spec expired?(t()) :: boolean()
    def expired?(%__MODULE__{expires_at: nil}), do: false

    def expired?(%__MODULE__{expires_at: expires_at}) do
      case DateTime.from_iso8601(expires_at) do
        {:ok, expiry, _} -> DateTime.compare(DateTime.utc_now(), expiry) == :gt
        _ -> false
      end
    end
  end

  defmodule MultiCurrencyAccount do
    @moduledoc "Typed struct for a multi-currency account."

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t(),
            type: String.t() | nil,
            currency: String.t(),
            iban: String.t() | nil,
            status: String.t() | nil,
            balance: String.t() | nil,
            created_at: String.t() | nil
          }

    defstruct [:id, :name, :type, :currency, :iban, :status, :balance, :created_at]

    @spec from_map(map()) :: t()
    def from_map(m) when is_map(m) do
      %__MODULE__{
        id: m["id"] || m["accountId"],
        name: m["name"] || m["accountName"],
        type: m["type"] || m["accountType"],
        currency: m["currencyCode"] || m["currency"],
        iban: m["iban"],
        status: m["status"],
        balance: m["balance"],
        created_at: m["createdAt"]
      }
    end
  end

  defmodule PaginatedResponse do
    @moduledoc """
    Generic typed wrapper for paginated API responses.

    ## Usage

        {:ok, body} = ClearBank.Accounts.list(client)
        paginated = ClearBank.Schemas.PaginatedResponse.from_map(body, "accounts", &ClearBank.Schemas.Account.from_map/1)
        paginated.data       # => [%Account{}, ...]
        paginated.total_count
        paginated.page_number
        paginated.page_size
    """

    @type t(item) :: %__MODULE__{
            data: [item],
            total_count: non_neg_integer(),
            page_number: pos_integer(),
            page_size: pos_integer()
          }

    defstruct data: [], total_count: 0, page_number: 1, page_size: 50

    @spec from_map(map(), String.t(), (map() -> any())) :: t(any())
    def from_map(body, data_key, item_parser) when is_map(body) and is_function(item_parser, 1) do
      items = Map.get(body, data_key, [])

      %__MODULE__{
        data: Enum.map(items, item_parser),
        total_count: Map.get(body, "totalCount") || Map.get(body, "total") || length(items),
        page_number: Map.get(body, "pageNumber") || Map.get(body, "page") || 1,
        page_size: Map.get(body, "pageSize") || Map.get(body, "size") || length(items)
      }
    end
  end
end
