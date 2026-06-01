defmodule ClearBank.Webhook.Events do
  @moduledoc """
  Typed structs for all known ClearBank webhook event payloads.

  Use these in your `ClearBank.Webhook.Handler` implementations for
  structured pattern matching and compile-time field documentation.

  ## Usage

      use ClearBank.Webhook.Handler

      @impl true
      def handle(%ClearBank.Webhook{type: "TransactionSettled", payload: payload}) do
        event = ClearBank.Webhook.Events.TransactionSettled.from_payload(payload)
        # event.transaction_id, event.amount, etc.
        :ok
      end

  ## All event types

  | Event type | Module | Trigger |
  |---|---|---|
  | `FITestEvent` | `FITestEvent` | POST /v1/Test |
  | `TransactionSettled` | `TransactionSettled` | Payment settled inbound or outbound |
  | `PaymentMessageAssessmentFailed` | `PaymentMessageAssessmentFailed` | Payment rejected pre-settlement |
  | `PaymentMessageValidationFailed` | `PaymentMessageValidationFailed` | Payment failed validation |
  | `TransactionRejected` | `TransactionRejected` | Payment rejected post-submission |
  | `FpsPaymentReturnCreated` | `FpsPaymentReturnCreated` | FPS return payment created |
  | `BacsPaymentCreated` | `BacsPaymentCreated` | Bacs payment created |
  | `BacsMandateCreated` | `BacsMandateCreated` | Direct Debit Instruction created |
  | `BacsMandateCancelled` | `BacsMandateCancelled` | DDI cancelled |
  | `BacsMandateMigrated` | `BacsMandateMigrated` | DDI migrated from another SUN |
  | `ChapsPaymentCreated` | `ChapsPaymentCreated` | CHAPS payment created |
  | `ChapsReturnCreated` | `ChapsReturnCreated` | CHAPS return created |
  | `CopOutboundResponse` | `CopOutboundResponse` | CoP name check response received |
  | `MccyTransactionCreated` | `MccyTransactionCreated` | Multi-currency transaction created |
  | `FxTradeCreated` | `FxTradeCreated` | FX trade executed |
  | `FxTradeSettled` | `FxTradeSettled` | FX trade settled |
  | `CustomerKycStatusChanged` | `CustomerKycStatusChanged` | Embedded Banking KYC status update |
  | `EmbeddedAccountCreated` | `EmbeddedAccountCreated` | Embedded account created |
  | `EmbeddedTransactionSettled` | `EmbeddedTransactionSettled` | Embedded account payment settled |
  """

  defmodule FITestEvent do
    @moduledoc "Test event fired by `POST /v1/Test` if subscribed."
    defstruct [:fired_at]

    @spec from_payload(map()) :: %__MODULE__{}
    def from_payload(payload) do
      %__MODULE__{fired_at: Map.get(payload, "firedAt")}
    end
  end

  defmodule TransactionSettled do
    @moduledoc """
    Fired when a payment settles on a GBP account (inbound or outbound).

    Covers: FPS, CHAPS, Bacs Direct Credit, internal transfers.
    """
    defstruct [
      :transaction_id,
      :account_id,
      :virtual_account_id,
      :amount,
      :currency,
      :direction,
      :type,
      :status,
      :reference,
      :counterpart_account,
      :counterpart_sort_code,
      :counterpart_account_number,
      :counterpart_name,
      :end_to_end_id,
      :timestamp
    ]

    @type t :: %__MODULE__{
            transaction_id: String.t(),
            account_id: String.t(),
            virtual_account_id: String.t() | nil,
            amount: String.t(),
            currency: String.t(),
            direction: :inbound | :outbound,
            type: String.t(),
            status: String.t(),
            reference: String.t() | nil,
            counterpart_account: String.t() | nil,
            counterpart_sort_code: String.t() | nil,
            counterpart_account_number: String.t() | nil,
            counterpart_name: String.t() | nil,
            end_to_end_id: String.t() | nil,
            timestamp: String.t()
          }

    @spec from_payload(map()) :: t()
    def from_payload(payload) do
      direction =
        case Map.get(payload, "direction") do
          "Inbound" -> :inbound
          "Outbound" -> :outbound
          _ -> nil
        end

      %__MODULE__{
        transaction_id: Map.get(payload, "transactionId"),
        account_id: Map.get(payload, "accountId"),
        virtual_account_id: Map.get(payload, "virtualAccountId"),
        amount: Map.get(payload, "amount"),
        currency: Map.get(payload, "currencyCode"),
        direction: direction,
        type: Map.get(payload, "type"),
        status: Map.get(payload, "status"),
        reference: Map.get(payload, "reference"),
        counterpart_account: Map.get(payload, "counterpartAccount"),
        counterpart_sort_code: Map.get(payload, "counterpartSortCode"),
        counterpart_account_number: Map.get(payload, "counterpartAccountNumber"),
        counterpart_name: Map.get(payload, "counterpartName"),
        end_to_end_id: Map.get(payload, "endToEndId"),
        timestamp: Map.get(payload, "timestamp")
      }
    end
  end

  defmodule PaymentMessageAssessmentFailed do
    @moduledoc "Fired when a payment is rejected during pre-settlement assessment."
    defstruct [:payment_id, :account_id, :reason_code, :reason_description, :timestamp]

    @spec from_payload(map()) :: %__MODULE__{}
    def from_payload(payload) do
      %__MODULE__{
        payment_id: Map.get(payload, "paymentId"),
        account_id: Map.get(payload, "accountId"),
        reason_code: Map.get(payload, "reasonCode"),
        reason_description: Map.get(payload, "reasonDescription"),
        timestamp: Map.get(payload, "timestamp")
      }
    end
  end

  defmodule PaymentMessageValidationFailed do
    @moduledoc "Fired when a payment fails validation before submission."
    defstruct [:payment_id, :account_id, :errors, :timestamp]

    @spec from_payload(map()) :: %__MODULE__{}
    def from_payload(payload) do
      %__MODULE__{
        payment_id: Map.get(payload, "paymentId"),
        account_id: Map.get(payload, "accountId"),
        errors: Map.get(payload, "errors", []),
        timestamp: Map.get(payload, "timestamp")
      }
    end
  end

  defmodule TransactionRejected do
    @moduledoc "Fired when a submitted payment is rejected post-processing."
    defstruct [
      :transaction_id,
      :account_id,
      :reason_code,
      :reason_description,
      :amount,
      :currency,
      :timestamp
    ]

    @spec from_payload(map()) :: %__MODULE__{}
    def from_payload(payload) do
      %__MODULE__{
        transaction_id: Map.get(payload, "transactionId"),
        account_id: Map.get(payload, "accountId"),
        reason_code: Map.get(payload, "reasonCode"),
        reason_description: Map.get(payload, "reasonDescription"),
        amount: Map.get(payload, "amount"),
        currency: Map.get(payload, "currencyCode"),
        timestamp: Map.get(payload, "timestamp")
      }
    end
  end

  defmodule FpsPaymentReturnCreated do
    @moduledoc "Fired when an FPS return payment is created."
    defstruct [
      :return_id,
      :original_transaction_id,
      :account_id,
      :amount,
      :currency,
      :reason_code,
      :timestamp
    ]

    @spec from_payload(map()) :: %__MODULE__{}
    def from_payload(payload) do
      %__MODULE__{
        return_id: Map.get(payload, "returnId"),
        original_transaction_id: Map.get(payload, "originalTransactionId"),
        account_id: Map.get(payload, "accountId"),
        amount: Map.get(payload, "amount"),
        currency: Map.get(payload, "currencyCode"),
        reason_code: Map.get(payload, "reasonCode"),
        timestamp: Map.get(payload, "timestamp")
      }
    end
  end

  defmodule BacsPaymentCreated do
    @moduledoc "Fired when a Bacs payment (Direct Credit or Direct Debit) is created."
    defstruct [
      :payment_id,
      :account_id,
      :virtual_account_id,
      :amount,
      :currency,
      :type,
      :service_user_number,
      :reference,
      :processing_date,
      :timestamp
    ]

    @spec from_payload(map()) :: %__MODULE__{}
    def from_payload(payload) do
      %__MODULE__{
        payment_id: Map.get(payload, "paymentId"),
        account_id: Map.get(payload, "accountId"),
        virtual_account_id: Map.get(payload, "virtualAccountId"),
        amount: Map.get(payload, "amount"),
        currency: Map.get(payload, "currencyCode"),
        type: Map.get(payload, "type"),
        service_user_number: Map.get(payload, "serviceUserNumber"),
        reference: Map.get(payload, "reference"),
        processing_date: Map.get(payload, "processingDate"),
        timestamp: Map.get(payload, "timestamp")
      }
    end
  end

  defmodule BacsMandateCreated do
    @moduledoc "Fired when a Direct Debit Instruction (DDI) is created."
    defstruct [
      :mandate_id,
      :account_id,
      :service_user_number,
      :reference,
      :payer_name,
      :status,
      :timestamp
    ]

    @spec from_payload(map()) :: %__MODULE__{}
    def from_payload(payload) do
      %__MODULE__{
        mandate_id: Map.get(payload, "mandateId"),
        account_id: Map.get(payload, "accountId"),
        service_user_number: Map.get(payload, "serviceUserNumber"),
        reference: Map.get(payload, "reference"),
        payer_name: Map.get(payload, "payerName"),
        status: Map.get(payload, "status"),
        timestamp: Map.get(payload, "timestamp")
      }
    end
  end

  defmodule BacsMandateCancelled do
    @moduledoc "Fired when a DDI is cancelled."
    defstruct [:mandate_id, :account_id, :reason, :timestamp]

    @spec from_payload(map()) :: %__MODULE__{}
    def from_payload(payload) do
      %__MODULE__{
        mandate_id: Map.get(payload, "mandateId"),
        account_id: Map.get(payload, "accountId"),
        reason: Map.get(payload, "reason"),
        timestamp: Map.get(payload, "timestamp")
      }
    end
  end

  defmodule BacsMandateMigrated do
    @moduledoc "Fired when a DDI is migrated from another SUN."
    defstruct [
      :mandate_id,
      :account_id,
      :old_service_user_number,
      :new_service_user_number,
      :timestamp
    ]

    @spec from_payload(map()) :: %__MODULE__{}
    def from_payload(payload) do
      %__MODULE__{
        mandate_id: Map.get(payload, "mandateId"),
        account_id: Map.get(payload, "accountId"),
        old_service_user_number: Map.get(payload, "oldServiceUserNumber"),
        new_service_user_number: Map.get(payload, "newServiceUserNumber"),
        timestamp: Map.get(payload, "timestamp")
      }
    end
  end

  defmodule ChapsPaymentCreated do
    @moduledoc "Fired when a CHAPS payment is created and accepted."
    defstruct [
      :instruction_id,
      :account_id,
      :amount,
      :currency,
      :creditor_name,
      :remittance_information,
      :timestamp
    ]

    @spec from_payload(map()) :: %__MODULE__{}
    def from_payload(payload) do
      %__MODULE__{
        instruction_id: Map.get(payload, "instructionId"),
        account_id: Map.get(payload, "accountId"),
        amount: Map.get(payload, "amount"),
        currency: Map.get(payload, "currencyCode"),
        creditor_name: Map.get(payload, "creditorName"),
        remittance_information: Map.get(payload, "remittanceInformation"),
        timestamp: Map.get(payload, "timestamp")
      }
    end
  end

  defmodule ChapsReturnCreated do
    @moduledoc "Fired when a CHAPS return payment is created."
    defstruct [
      :return_id,
      :original_instruction_id,
      :account_id,
      :amount,
      :reason_code,
      :timestamp
    ]

    @spec from_payload(map()) :: %__MODULE__{}
    def from_payload(payload) do
      %__MODULE__{
        return_id: Map.get(payload, "returnId"),
        original_instruction_id: Map.get(payload, "originalInstructionId"),
        account_id: Map.get(payload, "accountId"),
        amount: Map.get(payload, "amount"),
        reason_code: Map.get(payload, "reasonCode"),
        timestamp: Map.get(payload, "timestamp")
      }
    end
  end

  defmodule CopOutboundResponse do
    @moduledoc "Fired when a CoP outbound name verification response is received."
    defstruct [
      :request_id,
      :match_result,
      :account_name,
      :account_type,
      :sort_code,
      :account_number,
      :timestamp
    ]

    @type match_result ::
            :match | :close_match | :no_match | :account_type_mismatch | :partial_match | nil

    @type t :: %__MODULE__{
            request_id: String.t() | nil,
            match_result: match_result(),
            account_name: String.t() | nil,
            account_type: String.t() | nil,
            sort_code: String.t() | nil,
            account_number: String.t() | nil,
            timestamp: String.t() | nil
          }

    @spec from_payload(map()) :: t()
    def from_payload(payload) do
      %__MODULE__{
        request_id: Map.get(payload, "requestId"),
        match_result: parse_match_result(Map.get(payload, "matchResult")),
        account_name: Map.get(payload, "accountName"),
        account_type: Map.get(payload, "accountType"),
        sort_code: Map.get(payload, "sortCode"),
        account_number: Map.get(payload, "accountNumber"),
        timestamp: Map.get(payload, "timestamp")
      }
    end

    defp parse_match_result("MATC"), do: :match
    defp parse_match_result("CLOSE"), do: :close_match
    defp parse_match_result("NOMATCH"), do: :no_match
    defp parse_match_result("INAM"), do: :account_type_mismatch
    defp parse_match_result("PANM"), do: :partial_match
    defp parse_match_result(_), do: nil
  end

  defmodule MccyTransactionCreated do
    @moduledoc "Fired when a multi-currency transaction is created."
    defstruct [
      :transaction_id,
      :account_id,
      :virtual_account_id,
      :amount,
      :currency,
      :direction,
      :type,
      :reference,
      :timestamp
    ]

    @spec from_payload(map()) :: %__MODULE__{}
    def from_payload(payload) do
      %__MODULE__{
        transaction_id: Map.get(payload, "transactionId"),
        account_id: Map.get(payload, "accountId"),
        virtual_account_id: Map.get(payload, "virtualAccountId"),
        amount: Map.get(payload, "amount"),
        currency: Map.get(payload, "currencyCode"),
        direction: Map.get(payload, "direction"),
        type: Map.get(payload, "type"),
        reference: Map.get(payload, "reference"),
        timestamp: Map.get(payload, "timestamp")
      }
    end
  end

  defmodule FxTradeCreated do
    @moduledoc "Fired when an FX trade is executed."
    defstruct [
      :trade_id,
      :sell_account_id,
      :buy_account_id,
      :sell_currency,
      :buy_currency,
      :sell_amount,
      :buy_amount,
      :rate,
      :timestamp
    ]

    @spec from_payload(map()) :: %__MODULE__{}
    def from_payload(payload) do
      %__MODULE__{
        trade_id: Map.get(payload, "tradeId"),
        sell_account_id: Map.get(payload, "sellAccountId"),
        buy_account_id: Map.get(payload, "buyAccountId"),
        sell_currency: Map.get(payload, "sellCurrency"),
        buy_currency: Map.get(payload, "buyCurrency"),
        sell_amount: Map.get(payload, "sellAmount"),
        buy_amount: Map.get(payload, "buyAmount"),
        rate: Map.get(payload, "rate"),
        timestamp: Map.get(payload, "timestamp")
      }
    end
  end

  defmodule FxTradeSettled do
    @moduledoc "Fired when an FX trade settles (funds move between accounts)."
    defstruct [
      :trade_id,
      :sell_account_id,
      :buy_account_id,
      :sell_amount,
      :buy_amount,
      :timestamp
    ]

    @spec from_payload(map()) :: %__MODULE__{}
    def from_payload(payload) do
      %__MODULE__{
        trade_id: Map.get(payload, "tradeId"),
        sell_account_id: Map.get(payload, "sellAccountId"),
        buy_account_id: Map.get(payload, "buyAccountId"),
        sell_amount: Map.get(payload, "sellAmount"),
        buy_amount: Map.get(payload, "buyAmount"),
        timestamp: Map.get(payload, "timestamp")
      }
    end
  end

  defmodule CustomerKycStatusChanged do
    @moduledoc "Fired when an embedded customer's KYC status transitions."
    defstruct [:customer_id, :previous_status, :new_status, :reason, :timestamp]

    @type kyc_status :: :pending | :in_progress | :approved | :rejected | :requires_action | nil

    @type t :: %__MODULE__{
            customer_id: String.t() | nil,
            previous_status: kyc_status(),
            new_status: kyc_status(),
            reason: String.t() | nil,
            timestamp: String.t() | nil
          }

    @spec from_payload(map()) :: t()
    def from_payload(payload) do
      %__MODULE__{
        customer_id: Map.get(payload, "customerId"),
        previous_status: parse_status(Map.get(payload, "previousStatus")),
        new_status: parse_status(Map.get(payload, "newStatus")),
        reason: Map.get(payload, "reason"),
        timestamp: Map.get(payload, "timestamp")
      }
    end

    defp parse_status("Pending"), do: :pending
    defp parse_status("InProgress"), do: :in_progress
    defp parse_status("Approved"), do: :approved
    defp parse_status("Rejected"), do: :rejected
    defp parse_status("RequiresAction"), do: :requires_action
    defp parse_status(_), do: nil
  end

  defmodule EmbeddedAccountCreated do
    @moduledoc "Fired when a new embedded account is provisioned for a customer."
    defstruct [
      :account_id,
      :customer_id,
      :account_type,
      :account_name,
      :iban,
      :sort_code,
      :account_number,
      :timestamp
    ]

    @spec from_payload(map()) :: %__MODULE__{}
    def from_payload(payload) do
      %__MODULE__{
        account_id: Map.get(payload, "accountId"),
        customer_id: Map.get(payload, "customerId"),
        account_type: Map.get(payload, "accountType"),
        account_name: Map.get(payload, "accountName"),
        iban: Map.get(payload, "iban"),
        sort_code: Map.get(payload, "sortCode"),
        account_number: Map.get(payload, "accountNumber"),
        timestamp: Map.get(payload, "timestamp")
      }
    end
  end

  defmodule EmbeddedTransactionSettled do
    @moduledoc "Fired when a payment settles on an embedded customer's account."
    defstruct [
      :transaction_id,
      :account_id,
      :customer_id,
      :amount,
      :currency,
      :direction,
      :type,
      :reference,
      :counterpart_name,
      :timestamp
    ]

    @spec from_payload(map()) :: %__MODULE__{}
    def from_payload(payload) do
      %__MODULE__{
        transaction_id: Map.get(payload, "transactionId"),
        account_id: Map.get(payload, "accountId"),
        customer_id: Map.get(payload, "customerId"),
        amount: Map.get(payload, "amount"),
        currency: Map.get(payload, "currencyCode"),
        direction: Map.get(payload, "direction"),
        type: Map.get(payload, "type"),
        reference: Map.get(payload, "reference"),
        counterpart_name: Map.get(payload, "counterpartName"),
        timestamp: Map.get(payload, "timestamp")
      }
    end
  end

  @doc """
  Parses a webhook payload into a typed event struct based on the webhook type.

  Returns `{:ok, typed_event}` or `{:error, :unknown_event_type}`.

  ## Examples

      {:ok, %ClearBank.Webhook{type: type, payload: payload}} = ClearBank.Webhook.parse(raw)
      {:ok, event} = ClearBank.Webhook.Events.parse(type, payload)
  """
  @spec parse(String.t(), map()) :: {:ok, struct()} | {:error, :unknown_event_type}
  def parse(type, payload) do
    case Map.fetch(parsers(), type) do
      {:ok, parser} -> {:ok, parser.(payload)}
      :error -> {:error, :unknown_event_type}
    end
  end

  # Maps event type strings to their parser functions.
  # Using a module attribute map keeps cyclomatic complexity of parse/2 at 2.
  @parsers %{
    "FITestEvent" => &FITestEvent.from_payload/1,
    "TransactionSettled" => &TransactionSettled.from_payload/1,
    "PaymentMessageAssessmentFailed" => &PaymentMessageAssessmentFailed.from_payload/1,
    "PaymentMessageValidationFailed" => &PaymentMessageValidationFailed.from_payload/1,
    "TransactionRejected" => &TransactionRejected.from_payload/1,
    "FpsPaymentReturnCreated" => &FpsPaymentReturnCreated.from_payload/1,
    "BacsPaymentCreated" => &BacsPaymentCreated.from_payload/1,
    "BacsMandateCreated" => &BacsMandateCreated.from_payload/1,
    "BacsMandateCancelled" => &BacsMandateCancelled.from_payload/1,
    "BacsMandateMigrated" => &BacsMandateMigrated.from_payload/1,
    "ChapsPaymentCreated" => &ChapsPaymentCreated.from_payload/1,
    "ChapsReturnCreated" => &ChapsReturnCreated.from_payload/1,
    "CopOutboundResponse" => &CopOutboundResponse.from_payload/1,
    "MccyTransactionCreated" => &MccyTransactionCreated.from_payload/1,
    "FxTradeCreated" => &FxTradeCreated.from_payload/1,
    "FxTradeSettled" => &FxTradeSettled.from_payload/1,
    "CustomerKycStatusChanged" => &CustomerKycStatusChanged.from_payload/1,
    "EmbeddedAccountCreated" => &EmbeddedAccountCreated.from_payload/1,
    "EmbeddedTransactionSettled" => &EmbeddedTransactionSettled.from_payload/1
  }

  defp parsers, do: @parsers
end
