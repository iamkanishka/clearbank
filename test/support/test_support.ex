defmodule ClearBank.TestSupport do
  @moduledoc """
  Shared test helpers, fixtures, and a minimal RSA key pair for signature tests.
  """

  @doc """
  Generates a fresh RSA 2048 key pair as PEM binaries.
  Returns `{private_key_pem, public_key_pem}`.

  Note: Uses pure Erlang :public_key — no external tools required.
  """
  def generate_key_pair do
    private_key = :public_key.generate_key({:rsa, 2048, 65_537})

    private_pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
    private_pem = :public_key.pem_encode([private_pem_entry])

    public_key = extract_public_key(private_key)
    public_pem_entry = :public_key.pem_entry_encode(:RSAPublicKey, public_key)
    public_pem = :public_key.pem_encode([public_pem_entry])

    {private_pem, public_pem}
  end

  defp extract_public_key(private_key) do
    {:RSAPrivateKey, _, modulus, public_exponent, _, _, _, _, _, _, _} = private_key
    {:RSAPublicKey, modulus, public_exponent}
  end

  @doc """
  Returns a test `%ClearBank.Client{}` pointing at `base_url`.
  """
  def test_client(base_url, opts \\ []) do
    {priv_pem, _pub_pem} = generate_key_pair()

    ClearBank.Client.new(
      [
        api_token: "test-token-123",
        private_key: priv_pem,
        environment: :simulation,
        base_url: base_url
      ] ++ opts
    )
  end

  # --- Fixture data ---

  def account_fixture(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "acct-uuid-1",
        "name" => "Test Account",
        "type" => "YourFunds",
        "status" => "Active",
        "iban" => "GB29NWBK60161331926819",
        "sortCode" => "040004",
        "accountNumber" => "12345678",
        "currency" => "GBP",
        "balance" => "10000.00",
        "createdAt" => "2024-01-01T00:00:00Z"
      },
      overrides
    )
  end

  def virtual_account_fixture(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "virt-uuid-1",
        "name" => "Virtual Account 1",
        "iban" => "GB12CLRB04000412345679",
        "status" => "Active",
        "createdAt" => "2024-01-01T00:00:00Z"
      },
      overrides
    )
  end

  def transaction_fixture(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "txn-uuid-1",
        "amount" => "100.00",
        "currency" => "GBP",
        "type" => "FasterPaymentIn",
        "status" => "Settled",
        "createdAt" => "2024-01-15T12:00:00Z",
        "reference" => "TEST PAYMENT"
      },
      overrides
    )
  end

  def webhook_fixture(overrides \\ %{}) do
    Map.merge(
      %{
        "Type" => "TransactionSettled",
        "Version" => 1,
        "Payload" => %{"transactionId" => "txn-uuid-1", "amount" => "100.00"},
        "Nonce" => 123_456_789
      },
      overrides
    )
  end
end
