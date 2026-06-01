defmodule ClearBank.Auth.Signer do
  @moduledoc """
  Computes the `DigitalSignature` header value required by ClearBank for
  all POST / PATCH / PUT requests.

  ## Algorithm

    1. UTF-8 encode the raw request body.
    2. SHA-256 digest the encoded body.
    3. Sign the digest with the RSA private key using PKCS#1 v1.5 padding.
    4. Base64-encode the resulting signature bytes.

  The private key must be stored in a FIPS 140-2 level 2 compliant HSM
  in production. In simulation, any RSA key pair works.

  ## Usage

      body_json = Jason.encode!(payload)
      pem_bin   = File.read!("/path/to/private.pem")

      {:ok, signature} = ClearBank.Auth.Signer.sign(body_json, pem_bin)
      # => "Base64EncodedSignature..."

  """

  @type pem :: binary()
  @type signature :: String.t()

  @doc """
  Signs a request body and returns the Base64-encoded signature.

  Returns `{:ok, signature}` or `{:error, reason}`.
  """
  @spec sign(body :: iodata(), pem_or_key :: pem()) ::
          {:ok, signature()} | {:error, term()}
  def sign(body, pem_or_key) when is_binary(pem_or_key) or is_list(pem_or_key) do
    body_bin = IO.iodata_to_binary(body)

    with {:ok, private_key} <- decode_private_key(pem_or_key) do
      signature =
        body_bin
        |> hash_sha256()
        |> rsa_sign(private_key)
        |> Base.encode64()

      {:ok, signature}
    end
  end

  @doc """
  Like `sign/2` but raises on failure.
  """
  @spec sign!(body :: iodata(), pem_or_key :: pem()) :: signature()
  def sign!(body, pem_or_key) do
    case sign(body, pem_or_key) do
      {:ok, sig} -> sig
      {:error, reason} -> raise "ClearBank.Auth.Signer.sign! failed: #{inspect(reason)}"
    end
  end

  @doc """
  Verifies a `DigitalSignature` using ClearBank's public key.
  Used for verifying inbound webhook signatures.

  Returns `:ok` or `{:error, :invalid_signature}`.
  """
  @spec verify(body :: iodata(), signature_b64 :: String.t(), public_key_pem :: pem()) ::
          :ok | {:error, :invalid_signature | :bad_encoding}
  def verify(body, signature_b64, public_key_pem) do
    body_bin = IO.iodata_to_binary(body)

    with {:ok, sig_bytes} <- Base.decode64(signature_b64),
         {:ok, pub_key} <- decode_public_key(public_key_pem) do
      digest = hash_sha256(body_bin)

      case :public_key.verify(digest, :sha256, sig_bytes, pub_key) do
        true -> :ok
        false -> {:error, :invalid_signature}
      end
    else
      :error -> {:error, :bad_encoding}
      err -> err
    end
  end

  # ---

  defp decode_private_key(pem) do
    case :public_key.pem_decode(pem) do
      [{type, der, _} | _] when type in [:RSAPrivateKey, :PrivateKeyInfo] ->
        key = :public_key.pem_entry_decode({type, der, :not_encrypted})
        {:ok, key}

      [] ->
        {:error, :no_pem_entry_found}

      entries ->
        # try first entry regardless of type
        [{type, der, _} | _] = entries
        key = :public_key.pem_entry_decode({type, der, :not_encrypted})
        {:ok, key}
    end
  rescue
    e -> {:error, e}
  end

  defp decode_public_key(pem) do
    case :public_key.pem_decode(pem) do
      [{type, der, _} | _] ->
        key = :public_key.pem_entry_decode({type, der, :not_encrypted})
        {:ok, key}

      [] ->
        {:error, :no_pem_entry_found}
    end
  rescue
    e -> {:error, e}
  end

  defp hash_sha256(data), do: :crypto.hash(:sha256, data)

  defp rsa_sign(digest, private_key) do
    :public_key.sign(digest, :sha256, private_key)
  end
end
