defmodule ClearBank.MultiCurrency.AccountsTest do
  use ExUnit.Case, async: true

  alias ClearBank.MultiCurrency.Accounts
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "list/2" do
    test "returns multi-currency accounts", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/mccy/v2/Accounts", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"accounts" => [], "totalCount" => 0}))
      end)

      assert {:ok, %{"accounts" => []}} = Accounts.list(client)
    end

    test "passes currency filter as query param", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/mccy/v2/Accounts", fn conn ->
        assert conn.query_string =~ "currency=EUR"
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"accounts" => []}))
      end)

      Accounts.list(client, currency: "EUR")
    end
  end

  describe "create/2" do
    test "creates a multi-currency account with correct body", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/mccy/v2/Accounts", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["accountName"] == "EUR Operations"
        assert decoded["accountType"] == "YourFunds"
        assert decoded["currencyCode"] == "EUR"
        Plug.Conn.resp(conn, 201, Jason.encode!(%{"id" => "mccy-acct-1"}))
      end)

      assert {:ok, %{"id" => "mccy-acct-1"}} =
               Accounts.create(client,
                 account_name: "EUR Operations",
                 account_type: :your_funds,
                 currency: "EUR"
               )
    end

    test "raises for unknown account type" do
      {_priv, _} = TestSupport.generate_key_pair()
      client = TestSupport.test_client("http://localhost:9999")

      assert_raise KeyError, fn ->
        Accounts.create(client,
          account_name: "Bad",
          account_type: :nonexistent,
          currency: "EUR"
        )
      end
    end
  end
end

defmodule ClearBank.MultiCurrency.FxTradeTest do
  use ExUnit.Case, async: true

  alias ClearBank.MultiCurrency.FxTrade
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "execute/2" do
    test "executes a spot FX trade", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/fx/trades", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["sellAccountId"] == "eur-acct"
        assert decoded["buyAccountId"] == "gbp-acct"
        assert decoded["sellCurrency"] == "EUR"
        assert decoded["buyCurrency"] == "GBP"
        assert decoded["sellAmount"] == "10000.00"
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"tradeId" => "trade-1", "rate" => "0.86"}))
      end)

      assert {:ok, %{"tradeId" => "trade-1"}} =
               FxTrade.execute(client, %{
                 sell_account_id: "eur-acct",
                 buy_account_id: "gbp-acct",
                 sell_currency: "EUR",
                 buy_currency: "GBP",
                 sell_amount: "10000.00"
               })
    end
  end
end

defmodule ClearBank.MultiCurrency.FxTradeRfqTest do
  use ExUnit.Case, async: true

  alias ClearBank.MultiCurrency.FxTradeRfq
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "request_quote/2" do
    test "requests an RFQ and returns quote", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/fx/quotes", fn conn ->
        Plug.Conn.resp(
          conn,
          200,
          Jason.encode!(%{
            "quoteId" => "quote-uuid-1",
            "rate" => "0.86",
            "expiresAt" => "2024-01-01T12:05:00Z"
          })
        )
      end)

      assert {:ok, %{"quoteId" => "quote-uuid-1"}} =
               FxTradeRfq.request_quote(client, %{
                 sell_account_id: "eur-acct",
                 buy_account_id: "gbp-acct",
                 sell_currency: "EUR",
                 buy_currency: "GBP",
                 sell_amount: "50000.00"
               })
    end
  end

  describe "execute_quote/2" do
    test "executes an accepted quote", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/fx/quotes/quote-uuid-1/execute", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"status" => "Executed"}))
      end)

      assert {:ok, %{"status" => "Executed"}} = FxTradeRfq.execute_quote(client, "quote-uuid-1")
    end
  end

  describe "reject_quote/2" do
    test "rejects a quote", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "DELETE", "/v1/fx/quotes/quote-uuid-1", fn conn ->
        Plug.Conn.resp(conn, 204, "")
      end)

      assert {:ok, nil} = FxTradeRfq.reject_quote(client, "quote-uuid-1")
    end
  end
end

defmodule ClearBank.MultiCurrency.SepaCreditTransferTest do
  use ExUnit.Case, async: true

  alias ClearBank.MultiCurrency.SepaCreditTransfer
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "send/2" do
    test "sends an SCT UK payment with EUR currency hardcoded", %{bypass: bypass, client: client} do
      Bypass.expect_once(
        bypass,
        "POST",
        "/payments/sepa-credit-transfer/v2/customer-payments",
        fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          decoded = Jason.decode!(body)
          assert decoded["instructedAmount"]["currency"] == "EUR"
          assert decoded["creditor"]["iban"] == "DE89370400440532013000"
          Plug.Conn.resp(conn, 202, Jason.encode!(%{}))
        end
      )

      assert {:ok, _} =
               SepaCreditTransfer.send(client, %{
                 debtor_account_id: "eur-acct",
                 amount: "2500.00",
                 creditor_name: "Müller GmbH",
                 creditor_iban: "DE89370400440532013000",
                 creditor_bic: "COBADEFFXXX",
                 remittance_information: "Invoice DE-001"
               })
    end
  end
end

defmodule ClearBank.EmbeddedBanking.CustomersTest do
  use ExUnit.Case, async: true

  alias ClearBank.EmbeddedBanking.Customers
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "create_retail/2" do
    test "creates a retail customer with required fields", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/fin/customers/retail", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["firstName"] == "Alice"
        assert decoded["lastName"] == "Smith"
        assert decoded["dateOfBirth"] == "1990-05-15"
        Plug.Conn.resp(conn, 201, Jason.encode!(%{"customerId" => "cust-uuid-1"}))
      end)

      assert {:ok, %{"customerId" => "cust-uuid-1"}} =
               Customers.create_retail(client, %{
                 first_name: "Alice",
                 last_name: "Smith",
                 date_of_birth: "1990-05-15"
               })
    end

    test "includes optional fields when provided", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/fin/customers/retail", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["email"] == "alice@example.com"
        assert decoded["phone"] == "+447700900000"
        assert decoded["nationality"] == "GB"
        assert decoded["address"]["city"] == "London"
        Plug.Conn.resp(conn, 201, Jason.encode!(%{"customerId" => "cust-uuid-2"}))
      end)

      Customers.create_retail(client, %{
        first_name: "Alice",
        last_name: "Smith",
        date_of_birth: "1990-05-15",
        email: "alice@example.com",
        phone: "+447700900000",
        nationality: "GB",
        address: %{line1: "1 High St", city: "London", post_code: "SW1A 1AA", country: "GB"}
      })
    end
  end

  describe "create_legal_entity/2" do
    test "creates a legal entity customer", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v2/fin/customers/legal-entities", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["companyName"] == "ACME Ltd"
        assert decoded["registrationNumber"] == "12345678"
        assert decoded["registeredCountry"] == "GB"
        assert decoded["companyType"] == "PrivateLimitedCompany"
        Plug.Conn.resp(conn, 201, Jason.encode!(%{"customerId" => "entity-uuid-1"}))
      end)

      assert {:ok, %{"customerId" => "entity-uuid-1"}} =
               Customers.create_legal_entity(client, %{
                 company_name: "ACME Ltd",
                 registration_number: "12345678",
                 registered_country: "GB",
                 company_type: "PrivateLimitedCompany"
               })
    end

    test "includes beneficial owners when provided", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v2/fin/customers/legal-entities", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        [owner] = decoded["beneficialOwners"]
        assert owner["firstName"] == "Bob"
        assert owner["ownershipPercentage"] == 75
        Plug.Conn.resp(conn, 201, Jason.encode!(%{}))
      end)

      Customers.create_legal_entity(client, %{
        company_name: "Bob's Ltd",
        registration_number: "98765432",
        registered_country: "GB",
        company_type: "PrivateLimitedCompany",
        beneficial_owners: [
          %{
            first_name: "Bob",
            last_name: "Jones",
            date_of_birth: "1975-01-01",
            ownership_percentage: 75
          }
        ]
      })
    end
  end

  describe "get/2" do
    test "retrieves a customer by ID", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v1/fin/customers/cust-uuid-1", fn conn ->
        Plug.Conn.resp(
          conn,
          200,
          Jason.encode!(%{"customerId" => "cust-uuid-1", "firstName" => "Alice"})
        )
      end)

      assert {:ok, %{"customerId" => "cust-uuid-1"}} = Customers.get(client, "cust-uuid-1")
    end
  end
end

defmodule ClearBank.EmbeddedBanking.KycTest do
  use ExUnit.Case, async: true

  alias ClearBank.EmbeddedBanking.Kyc
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "get_status/2" do
    test "retrieves KYC status", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v1/fin/customers/cust-uuid-1/kyc", fn conn ->
        Plug.Conn.resp(
          conn,
          200,
          Jason.encode!(%{"status" => "Approved", "updatedAt" => "2024-01-15T10:00:00Z"})
        )
      end)

      assert {:ok, %{"status" => "Approved"}} = Kyc.get_status(client, "cust-uuid-1")
    end
  end

  describe "submit/3" do
    test "submits KYC data with PUT", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "PUT", "/v1/fin/customers/cust-uuid-1/kyc", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["idDocumentType"] == "Passport"
        assert decoded["idDocumentNumber"] == "123456789"
        assert decoded["idDocumentExpiry"] == "2030-01-01"
        assert decoded["idDocumentCountry"] == "GB"
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"status" => "InProgress"}))
      end)

      assert {:ok, %{"status" => "InProgress"}} =
               Kyc.submit(client, "cust-uuid-1", %{
                 id_document_type: "Passport",
                 id_document_number: "123456789",
                 id_document_expiry: "2030-01-01",
                 id_document_country: "GB"
               })
    end
  end
end
