defmodule ClearBank.TestEndpointsTest do
  use ExUnit.Case, async: true

  alias ClearBank.TestEndpoints
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "ping/1" do
    test "GET /v1/Test returns ok on 200", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v1/Test", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{}))
      end)

      assert {:ok, _} = TestEndpoints.ping(client)
    end

    test "returns error on 403", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v1/Test", fn conn ->
        Plug.Conn.resp(conn, 403, Jason.encode!(%{"message" => "Forbidden"}))
      end)

      assert {:error, %ClearBank.Error{status: 403}} = TestEndpoints.ping(client)
    end

    test "does NOT send DigitalSignature header (GET)", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v1/Test", fn conn ->
        sig = Plug.Conn.get_req_header(conn, "digitalsignature")
        assert sig == []
        Plug.Conn.resp(conn, 200, Jason.encode!(%{}))
      end)

      TestEndpoints.ping(client)
    end
  end

  describe "echo/2" do
    test "POST /v1/Test echoes body", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/Test", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["body"] == "hello world!"
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"Message" => "hello world!"}))
      end)

      assert {:ok, %{"Message" => "hello world!"}} = TestEndpoints.echo(client, "hello world!")
    end

    test "defaults body to 'ping'", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/Test", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["body"] == "ping"
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"Message" => "ping"}))
      end)

      TestEndpoints.echo(client)
    end

    test "sends DigitalSignature header on POST", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/Test", fn conn ->
        sig = Plug.Conn.get_req_header(conn, "digitalsignature")
        assert sig != []
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"Message" => "test"}))
      end)

      TestEndpoints.echo(client, "test")
    end
  end
end

defmodule ClearBank.Payments.InternalTransferTest do
  use ExUnit.Case, async: true

  alias ClearBank.Payments.InternalTransfer
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "send/2" do
    test "sends internal transfer with correct body", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v3/Payments/Transfer", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["debtorAccountId"] == "source-acct"
        assert decoded["creditorAccountId"] == "dest-acct"
        assert decoded["amount"] == "5000.00"
        assert decoded["currencyCode"] == "GBP"
        assert decoded["reference"] == "Daily sweep"

        Plug.Conn.resp(conn, 202, Jason.encode!(%{"transferId" => "xfer-1"}))
      end)

      assert {:ok, _} =
               InternalTransfer.send(client, %{
                 debtor_account_id: "source-acct",
                 creditor_account_id: "dest-acct",
                 amount: "5000.00",
                 currency: "GBP",
                 reference: "Daily sweep"
               })
    end

    test "includes virtual account IDs when provided", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v3/Payments/Transfer", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["creditorVirtualAccountId"] == "virt-uuid-1"
        Plug.Conn.resp(conn, 202, Jason.encode!(%{}))
      end)

      InternalTransfer.send(client, %{
        debtor_account_id: "hub-acct",
        creditor_account_id: "pool-acct",
        creditor_virtual_account_id: "virt-uuid-1",
        amount: "100.00",
        currency: "GBP"
      })
    end

    test "defaults currency to GBP", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v3/Payments/Transfer", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["currencyCode"] == "GBP"
        Plug.Conn.resp(conn, 202, Jason.encode!(%{}))
      end)

      InternalTransfer.send(client, %{
        debtor_account_id: "a",
        creditor_account_id: "b",
        amount: "1.00"
      })
    end
  end

  describe "send_bulk/2" do
    test "sends multiple transfers in one request", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v3/Payments/Transfer/Bulk", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert length(decoded["transfers"]) == 2
        Plug.Conn.resp(conn, 202, Jason.encode!(%{}))
      end)

      assert {:ok, _} =
               InternalTransfer.send_bulk(client, [
                 %{debtor_account_id: "a", creditor_account_id: "b", amount: "100.00"},
                 %{debtor_account_id: "a", creditor_account_id: "c", amount: "200.00"}
               ])
    end
  end
end

defmodule ClearBank.HTTP.RetryTest do
  use ExUnit.Case, async: true

  alias ClearBank.{Error, HTTP.Retry}

  describe "with_retry/2" do
    test "returns {:ok, result} immediately on success" do
      call_count = :counters.new(1, [])

      result =
        Retry.with_retry(fn ->
          :counters.add(call_count, 1, 1)
          {:ok, "success"}
        end)

      assert result == {:ok, "success"}
      assert :counters.get(call_count, 1) == 1
    end

    test "retries on retryable 500 error" do
      call_count = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            count = :counters.add(call_count, 1, 1)

            if count < 2 do
              {:error, %Error{status: 500, message: "Server error"}}
            else
              {:ok, "recovered"}
            end
          end,
          max_attempts: 3,
          base_delay_ms: 0
        )

      assert result == {:ok, "recovered"}
      assert :counters.get(call_count, 1) == 2
    end

    test "retries on 429 rate limit" do
      call_count = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            count = :counters.add(call_count, 1, 1)

            if count < 3 do
              {:error, %Error{status: 429, message: "Rate limited"}}
            else
              {:ok, "done"}
            end
          end,
          max_attempts: 3,
          base_delay_ms: 0
        )

      assert result == {:ok, "done"}
      assert :counters.get(call_count, 1) == 3
    end

    test "does NOT retry non-retryable 400 error" do
      call_count = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(call_count, 1, 1)
            {:error, %Error{status: 400, message: "Bad request"}}
          end,
          max_attempts: 3,
          base_delay_ms: 0
        )

      assert {:error, %Error{status: 400}} = result
      assert :counters.get(call_count, 1) == 1
    end

    test "does NOT retry 409 conflict" do
      call_count = :counters.new(1, [])

      Retry.with_retry(
        fn ->
          :counters.add(call_count, 1, 1)
          {:error, %Error{status: 409, message: "Conflict"}}
        end,
        max_attempts: 5,
        base_delay_ms: 0
      )

      assert :counters.get(call_count, 1) == 1
    end

    test "exhausts all attempts and returns last error" do
      error = %Error{status: 503, message: "Unavailable"}

      result =
        Retry.with_retry(
          fn -> {:error, error} end,
          max_attempts: 3,
          base_delay_ms: 0
        )

      assert {:error, ^error} = result
    end

    test "respects max_attempts: 1 (no retries)" do
      call_count = :counters.new(1, [])

      Retry.with_retry(
        fn ->
          :counters.add(call_count, 1, 1)
          {:error, %Error{status: 500, message: "error"}}
        end,
        max_attempts: 1,
        base_delay_ms: 0
      )

      assert :counters.get(call_count, 1) == 1
    end
  end
end

defmodule ClearBank.SchemasTest do
  use ExUnit.Case, async: true

  alias ClearBank.Schemas.Account
  alias ClearBank.Schemas.Customer
  alias ClearBank.Schemas.DirectDebitInstruction
  alias ClearBank.Schemas.EmbeddedAccount
  alias ClearBank.Schemas.FxQuote
  alias ClearBank.Schemas.MultiCurrencyAccount
  alias ClearBank.Schemas.PaginatedResponse
  alias ClearBank.Schemas.Transaction
  alias ClearBank.Schemas.VirtualAccount

  describe "Account.from_map/1" do
    test "parses a full account response" do
      m = %{
        "id" => "acct-1",
        "name" => "My Account",
        "type" => "SegregatedPooled",
        "status" => "Active",
        "iban" => "GB29NWBK60161331926819",
        "sortCode" => "040004",
        "accountNumber" => "12345678",
        "currency" => "GBP",
        "balance" => "10000.00",
        "copEnabled" => true,
        "createdAt" => "2024-01-01T00:00:00Z"
      }

      acct = Account.from_map(m)

      assert acct.id == "acct-1"
      assert acct.name == "My Account"
      assert acct.type == :segregated_pooled
      assert acct.status == :active
      assert acct.iban == "GB29NWBK60161331926819"
      assert acct.balance == "10000.00"
      assert acct.cop_enabled == true
    end

    test "handles alternative field names (accountId, accountName)" do
      m = %{
        "accountId" => "acct-2",
        "accountName" => "Alt Name",
        "accountType" => "YourFunds",
        "status" => "Active"
      }

      acct = Account.from_map(m)
      assert acct.id == "acct-2"
      assert acct.type == :your_funds
    end

    test "parses all account types" do
      types = %{
        "YourFunds" => :your_funds,
        "ClientMoneyPooled" => :client_money_pooled,
        "ClientMoneyDesignated" => :client_money_designated,
        "SegregatedPooled" => :segregated_pooled,
        "SegregatedDesignated" => :segregated_designated,
        "SafeguardedPooled" => :safeguarded_pooled,
        "SafeguardedDesignated" => :safeguarded_designated,
        "ClientSuspense" => :client_suspense
      }

      for {api_str, atom} <- types do
        acct = Account.from_map(%{"type" => api_str})
        assert acct.type == atom, "Expected #{api_str} -> #{atom}, got #{acct.type}"
      end
    end
  end

  describe "Transaction.from_map/1" do
    test "parses inbound transaction" do
      m = %{
        "id" => "txn-1",
        "accountId" => "acct-1",
        "amount" => "100.00",
        "currency" => "GBP",
        "direction" => "Inbound",
        "type" => "FasterPaymentIn",
        "status" => "Settled",
        "reference" => "Test ref",
        "createdAt" => "2024-01-15T12:00:00Z"
      }

      txn = Transaction.from_map(m)

      assert txn.id == "txn-1"
      assert txn.direction == :inbound
      assert txn.status == :settled
      assert txn.amount == "100.00"
    end

    test "parses outbound transaction" do
      m = %{"direction" => "Outbound", "status" => "Settled", "amount" => "50.00"}
      txn = Transaction.from_map(m)
      assert txn.direction == :outbound
    end
  end

  describe "FxQuote.expired?/1" do
    test "returns false for future expiry" do
      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
      quote = %FxQuote{expires_at: future}
      refute FxQuote.expired?(quote)
    end

    test "returns true for past expiry" do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.to_iso8601()
      quote = %FxQuote{expires_at: past}
      assert FxQuote.expired?(quote)
    end

    test "returns false when expires_at is nil" do
      refute FxQuote.expired?(%FxQuote{expires_at: nil})
    end
  end

  describe "Customer.from_map/1" do
    test "parses retail customer" do
      m = %{
        "customerId" => "cust-1",
        "customerType" => "Retail",
        "firstName" => "Alice",
        "lastName" => "Smith",
        "email" => "alice@example.com",
        "kycStatus" => "Approved"
      }

      cust = Customer.from_map(m)

      assert cust.id == "cust-1"
      assert cust.type == :retail
      assert cust.kyc_status == :approved
    end

    test "parses all KYC statuses" do
      statuses = %{
        "Pending" => :pending,
        "InProgress" => :in_progress,
        "Approved" => :approved,
        "Rejected" => :rejected,
        "RequiresAction" => :requires_action
      }

      for {api_str, atom} <- statuses do
        cust = Customer.from_map(%{"kycStatus" => api_str})
        assert cust.kyc_status == atom
      end
    end
  end

  describe "PaginatedResponse.from_map/3" do
    test "parses paginated account list" do
      body = %{
        "accounts" => [
          %{"id" => "acct-1", "type" => "YourFunds", "status" => "Active"},
          %{"id" => "acct-2", "type" => "SegregatedPooled", "status" => "Active"}
        ],
        "totalCount" => 2,
        "pageNumber" => 1,
        "pageSize" => 50
      }

      result = PaginatedResponse.from_map(body, "accounts", &Account.from_map/1)

      assert length(result.data) == 2
      assert result.total_count == 2
      assert result.page_number == 1
      assert hd(result.data).id == "acct-1"
    end
  end
end

defmodule ClearBank.Webhook.EventsTest do
  use ExUnit.Case, async: true

  alias ClearBank.Webhook.Events

  describe "parse/2" do
    test "parses FITestEvent" do
      assert {:ok, %Events.FITestEvent{}} = Events.parse("FITestEvent", %{})
    end

    test "parses TransactionSettled with inbound direction" do
      payload = %{
        "transactionId" => "txn-1",
        "accountId" => "acct-1",
        "amount" => "100.00",
        "currencyCode" => "GBP",
        "direction" => "Inbound",
        "type" => "FasterPaymentIn",
        "status" => "Settled",
        "timestamp" => "2024-01-15T12:00:00Z"
      }

      assert {:ok, %Events.TransactionSettled{} = event} =
               Events.parse("TransactionSettled", payload)

      assert event.transaction_id == "txn-1"
      assert event.direction == :inbound
      assert event.amount == "100.00"
    end

    test "parses TransactionSettled with outbound direction" do
      payload = %{"direction" => "Outbound", "amount" => "50.00"}
      {:ok, event} = Events.parse("TransactionSettled", payload)
      assert event.direction == :outbound
    end

    test "parses CopOutboundResponse with match results" do
      for {api_str, atom} <- [
            {"MATC", :match},
            {"CLOSE", :close_match},
            {"NOMATCH", :no_match},
            {"INAM", :account_type_mismatch},
            {"PANM", :partial_match}
          ] do
        {:ok, event} = Events.parse("CopOutboundResponse", %{"matchResult" => api_str})
        assert event.match_result == atom
      end
    end

    test "parses CustomerKycStatusChanged" do
      payload = %{
        "customerId" => "cust-1",
        "previousStatus" => "InProgress",
        "newStatus" => "Approved",
        "timestamp" => "2024-01-15T12:00:00Z"
      }

      {:ok, event} = Events.parse("CustomerKycStatusChanged", payload)
      assert event.customer_id == "cust-1"
      assert event.previous_status == :in_progress
      assert event.new_status == :approved
    end

    test "parses BacsPaymentCreated" do
      payload = %{
        "paymentId" => "pay-1",
        "accountId" => "acct-1",
        "amount" => "500.00",
        "serviceUserNumber" => "123456"
      }

      {:ok, event} = Events.parse("BacsPaymentCreated", payload)
      assert event.payment_id == "pay-1"
      assert event.service_user_number == "123456"
    end

    test "parses FxTradeCreated" do
      payload = %{
        "tradeId" => "trade-1",
        "sellCurrency" => "EUR",
        "buyCurrency" => "GBP",
        "rate" => "0.86"
      }

      {:ok, event} = Events.parse("FxTradeCreated", payload)
      assert event.trade_id == "trade-1"
      assert event.rate == "0.86"
    end

    test "returns error for unknown event type" do
      assert {:error, :unknown_event_type} = Events.parse("UnknownEvent", %{})
    end

    test "parses all 19 event types without error" do
      all_types = [
        "FITestEvent",
        "TransactionSettled",
        "PaymentMessageAssessmentFailed",
        "PaymentMessageValidationFailed",
        "TransactionRejected",
        "FpsPaymentReturnCreated",
        "BacsPaymentCreated",
        "BacsMandateCreated",
        "BacsMandateCancelled",
        "BacsMandateMigrated",
        "ChapsPaymentCreated",
        "ChapsReturnCreated",
        "CopOutboundResponse",
        "MccyTransactionCreated",
        "FxTradeCreated",
        "FxTradeSettled",
        "CustomerKycStatusChanged",
        "EmbeddedAccountCreated",
        "EmbeddedTransactionSettled"
      ]

      for type <- all_types do
        assert {:ok, _event} = Events.parse(type, %{}),
               "Expected parse to succeed for #{type}"
      end
    end
  end
end

defmodule ClearBank.HTTP.RequestIdTest do
  use ExUnit.Case, async: true

  alias ClearBank.{HTTP, TestSupport}

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "generate_request_id/0" do
    test "generates a UUID v4 formatted string" do
      id = HTTP.generate_request_id()

      assert String.match?(
               id,
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
             )
    end

    test "generates unique IDs each call" do
      ids = for _ <- 1..100, do: HTTP.generate_request_id()
      assert length(Enum.uniq(ids)) == 100
    end
  end

  describe "request_id override" do
    test "uses provided :request_id instead of generating one", %{bypass: bypass, client: client} do
      stable_id = "00000000-0000-4000-8000-000000000001"

      Bypass.expect_once(bypass, "GET", "/v3/Accounts", fn conn ->
        [req_id] = Plug.Conn.get_req_header(conn, "x-request-id")
        assert req_id == stable_id
        Plug.Conn.resp(conn, 200, Jason.encode!(%{}))
      end)

      HTTP.get(client, "/v3/Accounts", request_id: stable_id)
    end

    test "auto-generates request_id when not provided", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v3/Accounts", fn conn ->
        [req_id] = Plug.Conn.get_req_header(conn, "x-request-id")
        # Should be a valid UUID v4
        assert String.match?(
                 req_id,
                 ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
               )

        Plug.Conn.resp(conn, 200, Jason.encode!(%{}))
      end)

      HTTP.get(client, "/v3/Accounts")
    end
  end
end

defmodule ClearBank.EmbeddedBanking.AccountsExtendedTest do
  use ExUnit.Case, async: true

  alias ClearBank.EmbeddedBanking.Accounts
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "list/3" do
    test "lists accounts for a customer", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v1/fin/customers/cust-1/accounts", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"accounts" => []}))
      end)

      assert {:ok, _} = Accounts.list(client, "cust-1")
    end

    test "passes account_type filter", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v1/fin/customers/cust-1/accounts", fn conn ->
        assert conn.query_string =~ "accountType=Savings"
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"accounts" => []}))
      end)

      Accounts.list(client, "cust-1", account_type: "Savings")
    end
  end

  describe "close/2" do
    test "patches account status to Closed", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "PATCH", "/v1/fin/accounts/acct-1", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["status"] == "Closed"
        Plug.Conn.resp(conn, 200, Jason.encode!(%{}))
      end)

      assert {:ok, _} = Accounts.close(client, "acct-1")
    end
  end

  describe "list_transactions/3" do
    test "fetches transactions for embedded account", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v1/fin/accounts/acct-1/transactions", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"transactions" => []}))
      end)

      assert {:ok, _} = Accounts.list_transactions(client, "acct-1")
    end
  end

  describe "send_payment/2" do
    test "sends FPS payment from embedded account", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/fin/accounts/emb-acct-1/payments/fps", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["amount"] == "50.00"
        assert decoded["destination"]["name"] == "Bob"
        Plug.Conn.resp(conn, 202, Jason.encode!(%{}))
      end)

      assert {:ok, _} =
               Accounts.send_payment(client, %{
                 account_id: "emb-acct-1",
                 amount: "50.00",
                 currency: "GBP",
                 destination_sort_code: "040004",
                 destination_account_number: "12345678",
                 destination_account_name: "Bob",
                 reference: "Rent"
               })
    end
  end
end

defmodule ClearBank.EmbeddedBanking.CustomersExtendedTest do
  use ExUnit.Case, async: true

  alias ClearBank.EmbeddedBanking.Customers
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "list/2" do
    test "returns all customers", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v1/fin/customers", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"customers" => []}))
      end)

      assert {:ok, _} = Customers.list(client)
    end

    test "filters by customer_type", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v1/fin/customers", fn conn ->
        assert conn.query_string =~ "customerType=Retail"
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"customers" => []}))
      end)

      Customers.list(client, customer_type: "Retail")
    end
  end

  describe "update_sole_trader/3" do
    test "patches sole trader customer", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "PATCH", "/v2/fin/customers/sole-traders/cust-1", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["email"] == "new@example.com"
        Plug.Conn.resp(conn, 200, Jason.encode!(%{}))
      end)

      assert {:ok, _} =
               Customers.update_sole_trader(client, "cust-1", %{email: "new@example.com"})
    end
  end
end

defmodule ClearBank.MultiCurrency.AccountsExtendedTest do
  use ExUnit.Case, async: true

  alias ClearBank.MultiCurrency.Accounts
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "get_virtual/3" do
    test "fetches a specific virtual account", %{bypass: bypass, client: client} do
      Bypass.expect_once(
        bypass,
        "GET",
        "/mccy/v2/Accounts/acct-1/Virtual/virt-1",
        fn conn ->
          Plug.Conn.resp(conn, 200, Jason.encode!(%{"id" => "virt-1", "name" => "EUR Virtual"}))
        end
      )

      assert {:ok, %{"id" => "virt-1"}} = Accounts.get_virtual(client, "acct-1", "virt-1")
    end
  end
end
