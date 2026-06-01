defmodule ClearBank.Accounts.BacsPaymentDataTest do
  use ExUnit.Case, async: true

  alias ClearBank.Accounts.BacsPaymentData
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "list_collections/4" do
    test "fetches DDI collections for a real account", %{bypass: bypass, client: client} do
      Bypass.expect_once(
        bypass,
        "GET",
        "/v2/Accounts/acct-1/Mandates/mand-1/Collections",
        fn conn ->
          Plug.Conn.resp(conn, 200, Jason.encode!(%{"collections" => [], "totalCount" => 0}))
        end
      )

      assert {:ok, %{"collections" => []}} =
               BacsPaymentData.list_collections(client, "acct-1", "mand-1")
    end

    test "passes pagination params", %{bypass: bypass, client: client} do
      Bypass.expect_once(
        bypass,
        "GET",
        "/v2/Accounts/acct-1/Mandates/mand-1/Collections",
        fn conn ->
          assert conn.query_string =~ "pageSize=10"
          Plug.Conn.resp(conn, 200, Jason.encode!(%{"collections" => []}))
        end
      )

      BacsPaymentData.list_collections(client, "acct-1", "mand-1", page_size: 10)
    end

    test "returns error on 404", %{bypass: bypass, client: client} do
      Bypass.expect_once(
        bypass,
        "GET",
        "/v2/Accounts/acct-1/Mandates/bad-mand/Collections",
        fn conn ->
          Plug.Conn.resp(conn, 404, Jason.encode!(%{"message" => "Mandate not found"}))
        end
      )

      assert {:error, %ClearBank.Error{status: 404}} =
               BacsPaymentData.list_collections(client, "acct-1", "bad-mand")
    end
  end

  describe "list_returns/4" do
    test "fetches Bacs returns for a mandate", %{bypass: bypass, client: client} do
      Bypass.expect_once(
        bypass,
        "GET",
        "/v1/Accounts/acct-1/Mandates/mand-1/Returns",
        fn conn ->
          Plug.Conn.resp(conn, 200, Jason.encode!(%{"returns" => []}))
        end
      )

      assert {:ok, %{"returns" => []}} =
               BacsPaymentData.list_returns(client, "acct-1", "mand-1")
    end
  end
end

defmodule ClearBank.EmbeddedBanking.IsaTest do
  use ExUnit.Case, async: true

  alias ClearBank.EmbeddedBanking.Isa
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "create/2" do
    test "creates a Flexible Cash ISA", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/fin/accounts/cash-isa", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["customerId"] == "cust-uuid-1"
        assert decoded["accountName"] == "Alice's ISA"
        Plug.Conn.resp(conn, 201, Jason.encode!(%{"accountId" => "isa-uuid-1"}))
      end)

      assert {:ok, %{"accountId" => "isa-uuid-1"}} =
               Isa.create(client, %{
                 customer_id: "cust-uuid-1",
                 account_name: "Alice's ISA"
               })
    end
  end

  describe "transfer_in/3" do
    test "submits ISA transfer-in request", %{bypass: bypass, client: client} do
      Bypass.expect_once(
        bypass,
        "PUT",
        "/v1/fin/accounts/cash-isa/isa-uuid-1/transfer-in",
        fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          decoded = Jason.decode!(body)
          assert decoded["previousProviderName"] == "Barclays"
          assert decoded["previousProviderReference"] == "ISA-REF-123"
          assert decoded["transferAmount"] == "5000.00"
          assert decoded["transferType"] == "Cash"
          assert decoded["previousTaxYear"] == false
          Plug.Conn.resp(conn, 200, Jason.encode!(%{"status" => "Accepted"}))
        end
      )

      assert {:ok, %{"status" => "Accepted"}} =
               Isa.transfer_in(client, "isa-uuid-1", %{
                 previous_provider_name: "Barclays",
                 previous_provider_reference: "ISA-REF-123",
                 transfer_amount: "5000.00",
                 transfer_type: "Cash"
               })
    end

    test "sends previous_tax_year flag when true", %{bypass: bypass, client: client} do
      Bypass.expect_once(
        bypass,
        "PUT",
        "/v1/fin/accounts/cash-isa/isa-uuid-1/transfer-in",
        fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert Jason.decode!(body)["previousTaxYear"] == true
          Plug.Conn.resp(conn, 200, Jason.encode!(%{}))
        end
      )

      Isa.transfer_in(client, "isa-uuid-1", %{
        previous_provider_name: "HSBC",
        previous_provider_reference: "ISA-123",
        transfer_amount: "3000.00",
        transfer_type: "Cash",
        previous_tax_year: true
      })
    end
  end
end

defmodule ClearBank.EmbeddedBanking.InterestTest do
  use ExUnit.Case, async: true

  alias ClearBank.EmbeddedBanking.Interest
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "list_products/1" do
    test "returns available interest products", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v1/fin/interest/products", fn conn ->
        Plug.Conn.resp(
          conn,
          200,
          Jason.encode!(%{
            "products" => [
              %{"productId" => "prod-1", "name" => "Standard Saver", "rate" => "2.5"},
              %{"productId" => "prod-2", "name" => "Premium Saver", "rate" => "3.0"}
            ]
          })
        )
      end)

      assert {:ok, %{"products" => products}} = Interest.list_products(client)
      assert length(products) == 2
    end
  end

  describe "configure/3" do
    test "assigns an interest product to an account", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/fin/interest/accounts/acct-uuid-1", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["productId"] == "prod-1"
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"status" => "Configured"}))
      end)

      assert {:ok, %{"status" => "Configured"}} =
               Interest.configure(client, "acct-uuid-1", %{product_id: "prod-1"})
    end
  end
end

defmodule ClearBank.MultiCurrency.PaymentsTest do
  use ExUnit.Case, async: true

  alias ClearBank.MultiCurrency.Payments
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "send/2" do
    test "sends a single international payment", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/mccy/payments", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        [payment] = decoded["payments"]
        assert payment["accountId"] == "eur-acct-1"
        assert payment["amount"] == "1000.00"
        assert payment["currencyCode"] == "EUR"
        assert payment["creditor"]["name"] == "ACME GmbH"
        assert payment["creditor"]["iban"] == "DE89370400440532013000"
        Plug.Conn.resp(conn, 202, Jason.encode!(%{"batchId" => "batch-1"}))
      end)

      assert {:ok, _} =
               Payments.send(client, %{
                 account_id: "eur-acct-1",
                 amount: "1000.00",
                 currency: "EUR",
                 creditor_name: "ACME GmbH",
                 creditor_iban: "DE89370400440532013000",
                 creditor_bic: "COBADEFFXXX",
                 remittance_information: "Invoice EUR-001"
               })
    end
  end

  describe "send_bulk/2" do
    test "sends multiple payments in one batch", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/mccy/payments", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert length(Jason.decode!(body)["payments"]) == 2
        Plug.Conn.resp(conn, 202, Jason.encode!(%{}))
      end)

      payments = [
        %{
          account_id: "acct-1",
          amount: "500.00",
          currency: "EUR",
          creditor_name: "Alice",
          creditor_iban: "DE12345",
          creditor_bic: "COBADEFF",
          remittance_information: "P1"
        },
        %{
          account_id: "acct-1",
          amount: "750.00",
          currency: "EUR",
          creditor_name: "Bob",
          creditor_iban: "FR12345",
          creditor_bic: "BNPAFRPP",
          remittance_information: "P2"
        }
      ]

      assert {:ok, _} = Payments.send_bulk(client, payments)
    end
  end

  describe "cancel_batch/2" do
    test "sends DELETE to cancel a full batch", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "DELETE", "/v1/mccy/payments/batch-uuid-1", fn conn ->
        Plug.Conn.resp(conn, 204, "")
      end)

      assert {:ok, nil} = Payments.cancel_batch(client, "batch-uuid-1")
    end
  end

  describe "cancel_payment/3" do
    test "sends DELETE to cancel a single payment in a batch", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "DELETE", "/v1/mccy/payments/batch-uuid-1/e2e-id-1", fn conn ->
        Plug.Conn.resp(conn, 204, "")
      end)

      assert {:ok, nil} = Payments.cancel_payment(client, "batch-uuid-1", "e2e-id-1")
    end
  end

  describe "fund_account_sim/3" do
    test "funds account in simulation", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/mccy/inboundpayment/acct-unique-id", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["amount"] == "10000.00"
        assert decoded["currency"] == "EUR"
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"status" => "Accepted"}))
      end)

      assert {:ok, _} =
               Payments.fund_account_sim(client, "acct-unique-id", %{
                 amount: "10000.00",
                 currency: "EUR"
               })
    end
  end
end

defmodule ClearBank.Payments.ChequesTest do
  use ExUnit.Case, async: true

  alias ClearBank.Payments.Cheques
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "submit_deposit/2" do
    test "submits a cheque image deposit with required fields", %{bypass: bypass, client: client} do
      front_b64 = Base.encode64("fake-front-tiff-bytes")
      back_b64 = Base.encode64("fake-back-tiff-bytes")

      Bypass.expect_once(bypass, "POST", "/payments/cheques/v1/submit-deposit", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["accountId"] == "acct-uuid-1"
        assert decoded["amount"] == "500.00"
        assert decoded["currency"] == "GBP"
        assert decoded["chequeImageFront"] == front_b64
        assert decoded["chequeImageBack"] == back_b64
        assert decoded["micrLine"] == "000123|040004|12345678|"
        Plug.Conn.resp(conn, 202, Jason.encode!(%{"chequeId" => "chq-1"}))
      end)

      assert {:ok, %{"chequeId" => "chq-1"}} =
               Cheques.submit_deposit(client, %{
                 account_id: "acct-uuid-1",
                 amount: "500.00",
                 currency: "GBP",
                 cheque_image_front: front_b64,
                 cheque_image_back: back_b64,
                 micr_line: "000123|040004|12345678|"
               })
    end

    test "includes optional payee_name when provided", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/payments/cheques/v1/submit-deposit", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["payeeName"] == "Jane Smith"
        Plug.Conn.resp(conn, 202, Jason.encode!(%{}))
      end)

      Cheques.submit_deposit(client, %{
        account_id: "acct-uuid-1",
        amount: "100.00",
        currency: "GBP",
        cheque_image_front: Base.encode64("front"),
        cheque_image_back: Base.encode64("back"),
        micr_line: "123|040004|12345678|",
        payee_name: "Jane Smith"
      })
    end

    test "defaults currency to GBP", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/payments/cheques/v1/submit-deposit", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["currency"] == "GBP"
        Plug.Conn.resp(conn, 202, Jason.encode!(%{}))
      end)

      Cheques.submit_deposit(client, %{
        account_id: "acct-uuid-1",
        amount: "50.00",
        cheque_image_front: Base.encode64("f"),
        cheque_image_back: Base.encode64("b"),
        micr_line: "123|040004|12345678|"
      })
    end
  end
end

defmodule ClearBank.Payments.CrossBorderTest do
  use ExUnit.Case, async: true

  alias ClearBank.Payments.CrossBorder
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "send/2" do
    test "sends a cross-border GBP payment", %{bypass: bypass, client: client} do
      Bypass.expect_once(
        bypass,
        "POST",
        "/payments/cross-border-sterling/v3/payments",
        fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          decoded = Jason.decode!(body)
          assert decoded["accountId"] == "acct-uuid-1"
          assert decoded["amount"] == "1000.00"
          assert decoded["creditor"]["name"] == "ACME Corp"
          assert decoded["creditor"]["iban"] == "DE89370400440532013000"
          Plug.Conn.resp(conn, 202, Jason.encode!(%{"paymentId" => "pay-1"}))
        end
      )

      assert {:ok, _} =
               CrossBorder.send(client, %{
                 account_id: "acct-uuid-1",
                 amount: "1000.00",
                 currency: "GBP",
                 creditor_name: "ACME Corp",
                 creditor_iban: "DE89370400440532013000",
                 creditor_bic: "COBADEFFXXX",
                 remittance_information: "Invoice 1234"
               })
    end
  end
end

defmodule ClearBank.RateLimiterTest do
  use ExUnit.Case, async: false

  alias ClearBank.RateLimiter

  setup do
    # Start a fresh RateLimiter instance per test (not the app-level one)
    {:ok, pid} = GenServer.start_link(RateLimiter, %{rps: 5})
    %{pid: pid}
  end

  describe "check_rate/1" do
    test "allows requests within the rate limit", %{pid: pid} do
      for _ <- 1..5 do
        assert :ok = GenServer.call(pid, {:check_rate, 1})
      end
    end

    test "rejects when tokens exhausted", %{pid: pid} do
      # drain all 5 tokens
      for _ <- 1..5, do: GenServer.call(pid, {:check_rate, 1})
      # next should be rejected
      assert {:error, :rate_limited} = GenServer.call(pid, {:check_rate, 1})
    end

    test "accepts high-cost requests when tokens available", %{pid: pid} do
      assert :ok = GenServer.call(pid, {:check_rate, 3})
    end

    test "rejects high-cost requests when not enough tokens", %{pid: pid} do
      # Drain 4 tokens
      GenServer.call(pid, {:check_rate, 4})
      # Try to take 3 more but only 1 available
      assert {:error, :rate_limited} = GenServer.call(pid, {:check_rate, 3})
    end
  end
end

defmodule ClearBank.TypesTest do
  use ExUnit.Case, async: true

  alias ClearBank.Types

  describe "to_query/1" do
    test "encodes a map to query string" do
      result = Types.to_query(%{page_number: 2, page_size: 10})
      assert result =~ "page_number=2"
      assert result =~ "page_size=10"
    end

    test "drops nil values" do
      result = Types.to_query(%{page_number: 1, start_date: nil})
      assert result =~ "page_number=1"
      refute result =~ "start_date"
    end

    test "returns empty string for empty map" do
      assert Types.to_query(%{}) == ""
    end

    test "accepts keyword list" do
      result = Types.to_query(page_number: 3, page_size: 25)
      assert result =~ "page_number=3"
      assert result =~ "page_size=25"
    end
  end

  describe "build_path/2" do
    test "appends query string to path" do
      path = Types.build_path("/v3/Accounts", %{page_number: 1, page_size: 50})
      assert path =~ "/v3/Accounts?"
      assert path =~ "page_number=1"
    end

    test "returns bare path when params empty" do
      assert Types.build_path("/v3/Accounts", %{}) == "/v3/Accounts"
    end

    test "returns bare path when all params are nil" do
      assert Types.build_path("/v3/Accounts", %{page: nil}) == "/v3/Accounts"
    end
  end
end

defmodule ClearBank.Schemas.ExtendedTest do
  use ExUnit.Case, async: true

  alias ClearBank.Schemas.DirectDebitInstruction
  alias ClearBank.Schemas.EmbeddedAccount
  alias ClearBank.Schemas.MultiCurrencyAccount
  alias ClearBank.Schemas.VirtualAccount

  describe "VirtualAccount.from_map/1" do
    test "parses all fields" do
      m = %{
        "id" => "virt-1",
        "name" => "Customer A Virtual",
        "iban" => "GB12CLRB04000412345679",
        "sortCode" => "040004",
        "accountNumber" => "12345679",
        "status" => "Active",
        "owner" => "cust-ref-1",
        "createdAt" => "2024-01-01T00:00:00Z"
      }

      va = VirtualAccount.from_map(m)
      assert va.id == "virt-1"
      assert va.iban == "GB12CLRB04000412345679"
      assert va.owner == "cust-ref-1"
    end

    test "handles alternative field names" do
      m = %{"virtualAccountId" => "virt-2", "accountName" => "Alt"}
      va = VirtualAccount.from_map(m)
      assert va.id == "virt-2"
      assert va.name == "Alt"
    end
  end

  describe "DirectDebitInstruction.from_map/1" do
    test "parses DDI with nested payer details" do
      m = %{
        "id" => "mand-1",
        "accountId" => "acct-1",
        "serviceUserNumber" => "123456",
        "reference" => "CUST-001",
        "payerDetails" => %{
          "name" => "Alice Smith",
          "sortCode" => "040004",
          "accountNumber" => "12345678"
        },
        "status" => "Active",
        "createdAt" => "2024-01-01T00:00:00Z"
      }

      ddi = DirectDebitInstruction.from_map(m)
      assert ddi.id == "mand-1"
      assert ddi.service_user_number == "123456"
      assert ddi.payer_name == "Alice Smith"
      assert ddi.payer_sort_code == "040004"
    end
  end

  describe "EmbeddedAccount.from_map/1" do
    test "parses payment account" do
      m = %{
        "accountId" => "emb-acct-1",
        "customerId" => "cust-1",
        "accountName" => "Alice's Current",
        "accountType" => "Payment",
        "status" => "Active",
        "iban" => "GB29CLRB04000412345678",
        "currency" => "GBP",
        "balance" => "500.00"
      }

      acct = EmbeddedAccount.from_map(m)
      assert acct.id == "emb-acct-1"
      assert acct.type == :payment
      assert acct.status == :active
    end

    test "parses all embedded account types" do
      for {api_str, atom} <- [
            {"Payment", :payment},
            {"Savings", :savings},
            {"CashIsa", :cash_isa},
            {"Hub", :hub}
          ] do
        acct = EmbeddedAccount.from_map(%{"accountType" => api_str})
        assert acct.type == atom
      end
    end
  end

  describe "MultiCurrencyAccount.from_map/1" do
    test "parses a multi-currency account" do
      m = %{
        "id" => "mccy-1",
        "name" => "EUR Operations",
        "accountType" => "YourFunds",
        "currencyCode" => "EUR",
        "iban" => "GB12CLRB04000412345679",
        "status" => "Active",
        "balance" => "25000.00"
      }

      acct = MultiCurrencyAccount.from_map(m)
      assert acct.id == "mccy-1"
      assert acct.currency == "EUR"
      assert acct.balance == "25000.00"
    end
  end
end
