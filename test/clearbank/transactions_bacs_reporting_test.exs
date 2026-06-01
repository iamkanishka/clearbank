defmodule ClearBank.Accounts.TransactionsTest do
  use ExUnit.Case, async: true

  alias ClearBank.Accounts.Transactions
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "list_all/2" do
    test "returns institution-wide transactions", %{bypass: bypass, client: client} do
      txns = [
        TestSupport.transaction_fixture(),
        TestSupport.transaction_fixture(%{"id" => "txn-2"})
      ]

      Bypass.expect_once(bypass, "GET", "/v2/Transactions", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"transactions" => txns}))
      end)

      assert {:ok, %{"transactions" => result}} = Transactions.list_all(client)
      assert length(result) == 2
    end

    test "passes date filters as query params", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v2/Transactions", fn conn ->
        assert conn.query_string =~ "startDate=2024-01-01"
        assert conn.query_string =~ "endDate=2024-01-31"
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"transactions" => []}))
      end)

      Transactions.list_all(client, start_date: "2024-01-01", end_date: "2024-01-31")
    end
  end

  describe "list/3" do
    test "returns transactions for a specific account", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v2/Accounts/acct-uuid-1/Transactions", fn conn ->
        Plug.Conn.resp(
          conn,
          200,
          Jason.encode!(%{"transactions" => [TestSupport.transaction_fixture()]})
        )
      end)

      assert {:ok, %{"transactions" => [_]}} = Transactions.list(client, "acct-uuid-1")
    end
  end

  describe "get/3" do
    test "returns a specific transaction", %{bypass: bypass, client: client} do
      Bypass.expect_once(
        bypass,
        "GET",
        "/v2/Accounts/acct-uuid-1/Transactions/txn-uuid-1",
        fn conn ->
          Plug.Conn.resp(conn, 200, Jason.encode!(TestSupport.transaction_fixture()))
        end
      )

      assert {:ok, %{"id" => "txn-uuid-1"}} =
               Transactions.get(client, "acct-uuid-1", "txn-uuid-1")
    end
  end

  describe "list_virtual/4" do
    test "returns transactions for a virtual account", %{bypass: bypass, client: client} do
      Bypass.expect_once(
        bypass,
        "GET",
        "/v1/Accounts/acct-uuid-1/Virtual/virt-uuid-1/Transactions",
        fn conn ->
          Plug.Conn.resp(
            conn,
            200,
            Jason.encode!(%{"transactions" => []})
          )
        end
      )

      assert {:ok, _} = Transactions.list_virtual(client, "acct-uuid-1", "virt-uuid-1")
    end
  end
end

defmodule ClearBank.Payments.BacsDirectDebitTest do
  use ExUnit.Case, async: true

  alias ClearBank.Payments.BacsDirectDebit
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "create/3" do
    test "creates a DDI with correct body", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/Accounts/acct-uuid-1/Mandates", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["serviceUserNumber"] == "123456"
        assert decoded["reference"] == "CUST-001"
        assert decoded["payerDetails"]["name"] == "Alice Smith"
        assert decoded["payerDetails"]["sortCode"] == "040004"
        assert decoded["payerDetails"]["accountNumber"] == "12345678"
        Plug.Conn.resp(conn, 201, Jason.encode!(%{"mandateId" => "mand-uuid-1"}))
      end)

      assert {:ok, %{"mandateId" => "mand-uuid-1"}} =
               BacsDirectDebit.create(client, "acct-uuid-1", %{
                 service_user_number: "123456",
                 reference: "CUST-001",
                 payer_name: "Alice Smith",
                 payer_sort_code: "040004",
                 payer_account_number: "12345678"
               })
    end
  end

  describe "list/3" do
    test "returns DDIs for a real account", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v2/Accounts/acct-uuid-1/Mandates", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"mandates" => []}))
      end)

      assert {:ok, _} = BacsDirectDebit.list(client, "acct-uuid-1")
    end
  end

  describe "cancel/3" do
    test "sends DELETE to cancel a DDI", %{bypass: bypass, client: client} do
      Bypass.expect_once(
        bypass,
        "DELETE",
        "/v1/Accounts/acct-uuid-1/Mandates/mand-uuid-1",
        fn conn ->
          Plug.Conn.resp(conn, 204, "")
        end
      )

      assert {:ok, nil} = BacsDirectDebit.cancel(client, "acct-uuid-1", "mand-uuid-1")
    end
  end

  describe "create_virtual/4" do
    test "creates a DDI on a virtual account", %{bypass: bypass, client: client} do
      Bypass.expect_once(
        bypass,
        "POST",
        "/v1/Accounts/acct-uuid-1/Virtual/virt-uuid-1/Mandates",
        fn conn ->
          Plug.Conn.resp(conn, 201, Jason.encode!(%{"mandateId" => "mand-virt-1"}))
        end
      )

      assert {:ok, _} =
               BacsDirectDebit.create_virtual(client, "acct-uuid-1", "virt-uuid-1", %{
                 service_user_number: "654321",
                 reference: "VCUST-001",
                 payer_name: "Bob",
                 payer_sort_code: "060400",
                 payer_account_number: "87654321"
               })
    end
  end

  describe "cancel_virtual/4" do
    test "sends DELETE to cancel a virtual DDI", %{bypass: bypass, client: client} do
      Bypass.expect_once(
        bypass,
        "DELETE",
        "/v1/Accounts/acct-uuid-1/Virtual/virt-uuid-1/Mandates/mand-uuid-1",
        fn conn ->
          Plug.Conn.resp(conn, 204, "")
        end
      )

      assert {:ok, nil} =
               BacsDirectDebit.cancel_virtual(client, "acct-uuid-1", "virt-uuid-1", "mand-uuid-1")
    end
  end
end

defmodule ClearBank.Accounts.ReportingTest do
  use ExUnit.Case, async: true

  alias ClearBank.Accounts.Reporting
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "request_statement/2" do
    test "posts statement request with correct body", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/statementrequests", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["accountId"] == "acct-uuid-1"
        assert decoded["startDate"] == "2024-01-01"
        assert decoded["endDate"] == "2024-01-31"
        assert decoded["currency"] == "GBP"
        Plug.Conn.resp(conn, 202, Jason.encode!(%{"messageId" => "msg-uuid-1"}))
      end)

      assert {:ok, %{"messageId" => "msg-uuid-1"}} =
               Reporting.request_statement(client,
                 account_id: "acct-uuid-1",
                 start_date: "2024-01-01",
                 end_date: "2024-01-31"
               )
    end
  end

  describe "get_statement_page/3" do
    test "fetches a specific page of a statement", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v1/statementrequests/msg-uuid-1/pages/1", fn conn ->
        Plug.Conn.resp(
          conn,
          200,
          Jason.encode!(%{"page" => 1, "totalPages" => 3, "data" => "<camt.053 xml>"})
        )
      end)

      assert {:ok, %{"page" => 1, "totalPages" => 3}} =
               Reporting.get_statement_page(client, "msg-uuid-1", 1)
    end
  end

  describe "get_all_pages/2" do
    test "fetches all pages sequentially", %{bypass: bypass, client: client} do
      for page <- 1..3 do
        Bypass.expect_once(
          bypass,
          "GET",
          "/v1/statementrequests/msg-uuid-1/pages/#{page}",
          fn conn ->
            Plug.Conn.resp(
              conn,
              200,
              Jason.encode!(%{"page" => page, "totalPages" => 3, "data" => "page #{page} data"})
            )
          end
        )
      end

      assert {:ok, pages} = Reporting.get_all_pages(client, "msg-uuid-1")
      assert length(pages) == 3
      assert Enum.at(pages, 0)["page"] == 1
      assert Enum.at(pages, 2)["page"] == 3
    end

    test "returns single-page statement without extra calls", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v1/statementrequests/msg-uuid-1/pages/1", fn conn ->
        Plug.Conn.resp(
          conn,
          200,
          Jason.encode!(%{"page" => 1, "totalPages" => 1, "data" => "only page"})
        )
      end)

      assert {:ok, [page]} = Reporting.get_all_pages(client, "msg-uuid-1")
      assert page["totalPages"] == 1
    end
  end
end
