defmodule ClearBank.AccountsTest do
  use ExUnit.Case, async: true

  alias ClearBank.{Accounts, TestSupport}

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "list/2" do
    test "returns accounts on 200", %{bypass: bypass, client: client} do
      accounts = [TestSupport.account_fixture(), TestSupport.account_fixture(%{"id" => "acct-2"})]

      Bypass.expect_once(bypass, "GET", "/v3/Accounts", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"accounts" => accounts}))
      end)

      assert {:ok, %{"accounts" => result}} = Accounts.list(client)
      assert length(result) == 2
    end

    test "passes pagination params as query string", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v3/Accounts", fn conn ->
        assert conn.query_string =~ "pageNumber=2"
        assert conn.query_string =~ "pageSize=10"
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"accounts" => []}))
      end)

      assert {:ok, _} = Accounts.list(client, page_number: 2, page_size: 10)
    end

    test "returns error on 401", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v3/Accounts", fn conn ->
        Plug.Conn.resp(conn, 401, Jason.encode!(%{"message" => "Unauthorised"}))
      end)

      assert {:error, %ClearBank.Error{status: 401}} = Accounts.list(client)
    end
  end

  describe "get/2" do
    test "returns a single account", %{bypass: bypass, client: client} do
      account = TestSupport.account_fixture()

      Bypass.expect_once(bypass, "GET", "/v3/Accounts/acct-uuid-1", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(account))
      end)

      assert {:ok, result} = Accounts.get(client, "acct-uuid-1")
      assert result["id"] == "acct-uuid-1"
    end

    test "returns 404 error for unknown account", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v3/Accounts/nonexistent", fn conn ->
        Plug.Conn.resp(conn, 404, Jason.encode!(%{"message" => "Account not found"}))
      end)

      assert {:error, %ClearBank.Error{status: 404}} = Accounts.get(client, "nonexistent")
    end
  end

  describe "create/2" do
    test "creates account and returns 201", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v3/Accounts", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["accountName"] == "Test Pool"
        assert decoded["accountType"] == "SegregatedPooled"
        Plug.Conn.resp(conn, 201, Jason.encode!(TestSupport.account_fixture()))
      end)

      assert {:ok, _account} =
               Accounts.create(client,
                 account_name: "Test Pool",
                 account_type: :segregated_pooled
               )
    end

    test "includes DigitalSignature header in POST", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v3/Accounts", fn conn ->
        sig_header = Plug.Conn.get_req_header(conn, "digitalsignature")
        assert sig_header != []
        Plug.Conn.resp(conn, 201, Jason.encode!(TestSupport.account_fixture()))
      end)

      Accounts.create(client, account_name: "Signed Account", account_type: :your_funds)
    end

    test "includes Authorization header", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v3/Accounts", fn conn ->
        [auth] = Plug.Conn.get_req_header(conn, "authorization")
        assert auth =~ "Bearer test-token-123"
        Plug.Conn.resp(conn, 201, Jason.encode!(TestSupport.account_fixture()))
      end)

      Accounts.create(client, account_name: "Auth Test", account_type: :your_funds)
    end
  end

  describe "update/3" do
    test "sends PATCH with updated fields", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "PATCH", "/v1/Accounts/acct-uuid-1", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["accountName"] == "Renamed Account"
        Plug.Conn.resp(conn, 200, Jason.encode!(%{}))
      end)

      assert {:ok, _} = Accounts.update(client, "acct-uuid-1", account_name: "Renamed Account")
    end
  end

  describe "create_virtual/3" do
    test "creates virtual account under a real account", %{bypass: bypass, client: client} do
      virtual = TestSupport.virtual_account_fixture()

      Bypass.expect_once(bypass, "POST", "/v2/Accounts/acct-uuid-1/Virtual", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["accountName"] == "Customer Virtual"
        Plug.Conn.resp(conn, 201, Jason.encode!(virtual))
      end)

      assert {:ok, result} =
               Accounts.create_virtual(client, "acct-uuid-1", account_name: "Customer Virtual")

      assert result["id"] == "virt-uuid-1"
    end
  end

  describe "list_virtual/3" do
    test "returns virtual accounts", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v2/Accounts/acct-uuid-1/Virtual", fn conn ->
        Plug.Conn.resp(
          conn,
          200,
          Jason.encode!(%{"virtualAccounts" => [TestSupport.virtual_account_fixture()]})
        )
      end)

      assert {:ok, %{"virtualAccounts" => [_]}} =
               Accounts.list_virtual(client, "acct-uuid-1")
    end
  end
end
