defmodule ClearBank.Payments.FasterPaymentsTest do
  use ExUnit.Case, async: true

  alias ClearBank.Payments.FasterPayments
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "send/2" do
    test "sends a single FPS payment with correct body", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v3/Payments/FPS", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["accountId"] == "acct-uuid-1"
        [payment] = decoded["payments"]
        assert payment["amount"] == "250.00"
        assert payment["currencyCode"] == "GBP"
        assert payment["destination"]["sortCode"] == "040004"
        assert payment["destination"]["accountNumber"] == "12345678"
        assert payment["destination"]["name"] == "Jane Smith"
        assert payment["reference"] == "INV-001"
        assert payment["paymentType"] == "SIP"
        assert payment["enforceSendToScheme"] == false

        Plug.Conn.resp(conn, 202, Jason.encode!(%{"status" => "Accepted"}))
      end)

      assert {:ok, _} =
               FasterPayments.send(client, %{
                 account_id: "acct-uuid-1",
                 amount: "250.00",
                 currency: "GBP",
                 destination_sort_code: "040004",
                 destination_account_number: "12345678",
                 destination_account_name: "Jane Smith",
                 reference: "INV-001"
               })
    end

    test "omits nil optional fields", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v3/Payments/FPS", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        [payment] = decoded["payments"]
        refute Map.has_key?(payment, "reference")
        refute Map.has_key?(payment, "endToEndId")
        Plug.Conn.resp(conn, 202, Jason.encode!(%{}))
      end)

      FasterPayments.send(client, %{
        account_id: "acct-uuid-1",
        amount: "10.00",
        currency: "GBP",
        destination_sort_code: "040004",
        destination_account_number: "12345678",
        destination_account_name: "Bob"
      })
    end

    test "enforces send to scheme when flag is true", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v3/Payments/FPS", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        [payment] = Jason.decode!(body)["payments"]
        assert payment["enforceSendToScheme"] == true
        Plug.Conn.resp(conn, 202, Jason.encode!(%{}))
      end)

      FasterPayments.send(client, %{
        account_id: "acct-uuid-1",
        amount: "1.00",
        currency: "GBP",
        destination_sort_code: "040004",
        destination_account_number: "12345678",
        destination_account_name: "Alice",
        enforce_send_to_scheme: true
      })
    end

    test "maps payment type atoms to API strings", %{bypass: bypass, client: client} do
      for {atom, expected_str} <- [sip: "SIP", sop: "SOP", fdp: "FDP"] do
        Bypass.expect_once(bypass, "POST", "/v3/Payments/FPS", fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          [payment] = Jason.decode!(body)["payments"]
          assert payment["paymentType"] == expected_str
          Plug.Conn.resp(conn, 202, Jason.encode!(%{}))
        end)

        FasterPayments.send(client, %{
          account_id: "acct-uuid-1",
          amount: "1.00",
          currency: "GBP",
          destination_sort_code: "040004",
          destination_account_number: "12345678",
          destination_account_name: "Test",
          payment_type: atom
        })
      end
    end

    test "returns error on 400", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v3/Payments/FPS", fn conn ->
        Plug.Conn.resp(
          conn,
          400,
          Jason.encode!(%{"title" => "Bad request", "errors" => %{"amount" => ["invalid"]}})
        )
      end)

      assert {:error, %ClearBank.Error{status: 400}} =
               FasterPayments.send(client, %{
                 account_id: "acct-uuid-1",
                 amount: "bad",
                 currency: "GBP",
                 destination_sort_code: "040004",
                 destination_account_number: "12345678",
                 destination_account_name: "Test"
               })
    end

    test "returns error on 409 duplicate", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v3/Payments/FPS", fn conn ->
        Plug.Conn.resp(conn, 409, Jason.encode!(%{"message" => "Duplicate X-Request-Id"}))
      end)

      assert {:error, %ClearBank.Error{status: 409}} =
               FasterPayments.send(client, %{
                 account_id: "acct-uuid-1",
                 amount: "1.00",
                 currency: "GBP",
                 destination_sort_code: "040004",
                 destination_account_number: "12345678",
                 destination_account_name: "Test"
               })
    end
  end

  describe "send_bulk/3" do
    test "sends multiple payments in one request", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v3/Payments/FPS", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["accountId"] == "acct-uuid-1"
        assert length(decoded["payments"]) == 2
        Plug.Conn.resp(conn, 202, Jason.encode!(%{}))
      end)

      payments = [
        %{
          amount: "100.00",
          currency: "GBP",
          destination_sort_code: "040004",
          destination_account_number: "11111111",
          destination_account_name: "Alice"
        },
        %{
          amount: "200.00",
          currency: "GBP",
          destination_sort_code: "060400",
          destination_account_number: "22222222",
          destination_account_name: "Bob"
        }
      ]

      assert {:ok, _} = FasterPayments.send_bulk(client, "acct-uuid-1", payments)
    end
  end
end

defmodule ClearBank.Payments.ChapsTest do
  use ExUnit.Case, async: true

  alias ClearBank.Payments.Chaps
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "send/2" do
    test "sends CHAPS payment with structured body", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/payments/chaps/v5/customer-payments", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["debtorAccountId"] == "acct-uuid-1"
        assert decoded["instructedAmount"]["amount"] == "500000.00"
        assert decoded["instructedAmount"]["currency"] == "GBP"
        assert decoded["creditor"]["name"] == "Conveyancing Ltd"
        assert decoded["creditor"]["account"]["sortCode"] == "200000"
        assert decoded["creditor"]["address"]["country"] == "GB"
        assert decoded["remittanceInformation"] == "PROP PURCHASE"

        Plug.Conn.resp(conn, 202, Jason.encode!(%{}))
      end)

      assert {:ok, _} =
               Chaps.send(client, %{
                 debtor_account_id: "acct-uuid-1",
                 amount: "500000.00",
                 currency: "GBP",
                 creditor_name: "Conveyancing Ltd",
                 creditor_sort_code: "200000",
                 creditor_account_number: "55779911",
                 creditor_address: %{
                   street_name: "High Street",
                   building_number: "1",
                   post_code: "SW1A 1AA",
                   town_name: "London",
                   country: "GB"
                 },
                 remittance_information: "PROP PURCHASE"
               })
    end

    test "returns error on 422 unprocessable", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/payments/chaps/v5/customer-payments", fn conn ->
        Plug.Conn.resp(
          conn,
          422,
          Jason.encode!(%{"title" => "Unprocessable", "detail" => "Invalid sort code"})
        )
      end)

      assert {:error, %ClearBank.Error{status: 422}} =
               Chaps.send(client, %{
                 debtor_account_id: "acct-uuid-1",
                 amount: "1.00",
                 currency: "GBP",
                 creditor_name: "Test",
                 creditor_sort_code: "000000",
                 creditor_account_number: "00000000",
                 creditor_address: %{country: "GB", town_name: "London"},
                 remittance_information: "Test"
               })
    end
  end

  describe "return_payment/2" do
    test "sends CHAPS return with correct body", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/payments/chaps/v5/return-payments", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["originalInstructionId"] == "inst-uuid-1"
        assert decoded["returnReasonCode"] == "CUST"
        Plug.Conn.resp(conn, 202, Jason.encode!(%{}))
      end)

      assert {:ok, _} =
               Chaps.return_payment(client, %{
                 original_instruction_id: "inst-uuid-1",
                 debtor_account_id: "acct-uuid-1",
                 return_reason_code: "CUST",
                 amount: "500000.00",
                 currency: "GBP"
               })
    end
  end
end

defmodule ClearBank.Payments.ConfirmationOfPayeeTest do
  use ExUnit.Case, async: true

  alias ClearBank.Payments.ConfirmationOfPayee
  alias ClearBank.TestSupport

  setup do
    bypass = Bypass.open()
    client = TestSupport.test_client("http://localhost:#{bypass.port}")
    %{bypass: bypass, client: client}
  end

  describe "check/2" do
    test "sends CoP check with correct body", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/Cop/outbound/name-verification", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["accountName"] == "Jane Smith"
        assert decoded["sortCode"] == "040004"
        assert decoded["accountNumber"] == "12345678"
        assert decoded["accountType"] == "Personal"
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"matchResult" => "MATC"}))
      end)

      assert {:ok, %{"matchResult" => "MATC"}} =
               ConfirmationOfPayee.check(client, %{
                 account_name: "Jane Smith",
                 sort_code: "040004",
                 account_number: "12345678",
                 account_type: "Personal"
               })
    end

    test "defaults account_type to Personal", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v1/Cop/outbound/name-verification", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["accountType"] == "Personal"
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"matchResult" => "NOMATCH"}))
      end)

      ConfirmationOfPayee.check(client, %{
        account_name: "Bob",
        sort_code: "040004",
        account_number: "12345678"
      })
    end
  end

  describe "opt_out_account/2" do
    test "sends PUT to opt out a real account", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "PUT", "/v1/Cop/opt/accounts/acct-uuid-1", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["optOut"] == true
        Plug.Conn.resp(conn, 200, Jason.encode!(%{}))
      end)

      assert {:ok, _} = ConfirmationOfPayee.opt_out_account(client, "acct-uuid-1")
    end
  end

  describe "opt_out_virtual/3" do
    test "sends PUT to opt out a virtual account", %{bypass: bypass, client: client} do
      Bypass.expect_once(
        bypass,
        "PUT",
        "/v1/Cop/opt/accounts/acct-uuid-1/virtual/virt-uuid-1",
        fn conn ->
          Plug.Conn.resp(conn, 200, Jason.encode!(%{}))
        end
      )

      assert {:ok, _} =
               ConfirmationOfPayee.opt_out_virtual(client, "acct-uuid-1", "virt-uuid-1")
    end
  end
end
