defmodule ClearBank.Auth.SignerTest do
  use ExUnit.Case, async: true

  alias ClearBank.Auth.Signer
  alias ClearBank.TestSupport

  setup do
    {private_pem, public_pem} = TestSupport.generate_key_pair()
    %{private_pem: private_pem, public_pem: public_pem}
  end

  describe "sign/2" do
    test "returns {:ok, base64_string} for valid body and key", %{private_pem: priv} do
      assert {:ok, sig} = Signer.sign(~s({"key":"value"}), priv)
      assert is_binary(sig)
      assert Base.decode64(sig) != :error
    end

    test "returns different signatures for different bodies", %{private_pem: priv} do
      {:ok, sig1} = Signer.sign("body one", priv)
      {:ok, sig2} = Signer.sign("body two", priv)
      assert sig1 != sig2
    end

    test "returns same signature for same body and key (deterministic RSA PKCS1 v1.5)",
         %{private_pem: priv} do
      {:ok, sig1} = Signer.sign("consistent body", priv)
      {:ok, sig2} = Signer.sign("consistent body", priv)
      assert sig1 == sig2
    end

    test "accepts iodata as body", %{private_pem: priv} do
      assert {:ok, _sig} = Signer.sign(["hello", " ", "world"], priv)
    end

    test "returns error for invalid PEM" do
      assert {:error, _} = Signer.sign("body", "not-a-pem")
    end
  end

  describe "sign!/2" do
    test "returns the signature string directly", %{private_pem: priv} do
      sig = Signer.sign!("body", priv)
      assert is_binary(sig)
    end

    test "raises for invalid PEM" do
      assert_raise RuntimeError, ~r/sign! failed/, fn ->
        Signer.sign!("body", "invalid")
      end
    end
  end

  describe "verify/3" do
    test "returns :ok for a valid signature", %{private_pem: priv, public_pem: pub} do
      body = ~s({"nonce": 12345})
      {:ok, sig} = Signer.sign(body, priv)
      assert :ok = Signer.verify(body, sig, pub)
    end

    test "returns {:error, :invalid_signature} for wrong body", %{
      private_pem: priv,
      public_pem: pub
    } do
      {:ok, sig} = Signer.sign("original body", priv)
      assert {:error, :invalid_signature} = Signer.verify("tampered body", sig, pub)
    end

    test "returns {:error, :invalid_signature} for wrong key", %{private_pem: priv} do
      {_other_priv, other_pub} = TestSupport.generate_key_pair()
      {:ok, sig} = Signer.sign("body", priv)
      assert {:error, :invalid_signature} = Signer.verify("body", sig, other_pub)
    end

    test "returns {:error, :bad_encoding} for non-base64 signature", %{public_pem: pub} do
      assert {:error, :bad_encoding} = Signer.verify("body", "!!!not-base64!!!", pub)
    end
  end
end
