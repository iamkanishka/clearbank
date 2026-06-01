defmodule Mix.Tasks.Clearbank.Gen.Keys do
  @moduledoc """
  Generates an RSA 2048-bit key pair suitable for ClearBank API authentication.

  ## Usage

      mix clearbank.gen.keys

      # Custom output directory
      mix clearbank.gen.keys --dir priv/certs

      # Custom filenames
      mix clearbank.gen.keys --private private.pem --public public.pem

      # Generate CSR for upload to ClearBank Portal
      mix clearbank.gen.keys --csr --common-name "My Institution"

  ## Output files

  By default, writes to `priv/clearbank/`:

    * `private_key.pem` — keep secret, store in HSM in production
    * `public_key.pem` — extracted public key
    * `clearbank.csr` — Certificate Signing Request (if `--csr` flag used)

  ## Security

    - **Never commit `private_key.pem` to version control**
    - In production, the private key must reside in a FIPS 140-2 level 2 compliant HSM
    - In simulation, any RSA 2048-bit key pair is acceptable

  ## Next steps

  1. Upload `clearbank.csr` to the ClearBank Portal under
     **Institution > Certificates and Tokens > Generate API Token**
  2. Copy the API token (shown only once)
  3. Configure in `config/runtime.exs`:

         config :clearbank,
           api_token: System.fetch_env!("CLEARBANK_API_TOKEN"),
           private_key_path: System.fetch_env!("CLEARBANK_PRIVATE_KEY_PATH")
  """

  # Mix.Task is not included in the default Dialyzer PLT for libraries.
  # :no_behaviour_info suppresses the callback_info_missing warning that
  # Dialyzer emits when it cannot find the behaviour definition in the PLT.
  # This is the canonical fix used by Elixir core and major libraries
  # (Ecto, Phoenix) for all Mix task modules.

  use Mix.Task

  @switches [
    dir: :string,
    private: :string,
    public: :string,
    csr: :boolean,
    common_name: :string,
    force: :boolean
  ]

  @spec run([String.t()]) :: :ok
  def run(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, switches: @switches)

    dir = Keyword.get(opts, :dir, "priv/clearbank")
    private_file = Keyword.get(opts, :private, "private_key.pem")
    public_file = Keyword.get(opts, :public, "public_key.pem")
    generate_csr = Keyword.get(opts, :csr, false)
    common_name = Keyword.get(opts, :common_name, "ClearBank Institution")
    force = Keyword.get(opts, :force, false)

    private_path = Path.join(dir, private_file)
    public_path = Path.join(dir, public_file)
    csr_path = Path.join(dir, "clearbank.csr")

    File.mkdir_p!(dir)
    check_existing_key(private_path, force)

    shell_info("Generating RSA 2048-bit key pair...")

    private_key = :public_key.generate_key({:rsa, 2048, 65_537})
    {private_pem, public_pem} = encode_key_pair(private_key)

    File.write!(private_path, private_pem)
    shell_info("  ✓ Private key written to #{private_path}")

    File.write!(public_path, public_pem)
    shell_info("  ✓ Public key written to #{public_path}")

    maybe_write_csr(generate_csr, private_key, common_name, csr_path)
    write_gitignore(dir)
    print_next_steps(private_path, generate_csr, csr_path, common_name)
  end

  # ---

  defp check_existing_key(private_path, force) do
    if not force and File.exists?(private_path) do
      raise_error(
        "#{private_path} already exists. Use --force to overwrite.\n" <>
          "Overwriting a key pair in use will invalidate your ClearBank API token."
      )
    end
  end

  defp encode_key_pair(private_key) do
    private_pem =
      private_key
      |> then(&:public_key.pem_entry_encode(:RSAPrivateKey, &1))
      |> List.wrap()
      |> :public_key.pem_encode()

    {:RSAPrivateKey, _, modulus, pub_exp, _, _, _, _, _, _, _} = private_key
    public_key = {:RSAPublicKey, modulus, pub_exp}

    public_pem =
      public_key
      |> then(&:public_key.pem_entry_encode(:RSAPublicKey, &1))
      |> List.wrap()
      |> :public_key.pem_encode()

    {private_pem, public_pem}
  end

  defp maybe_write_csr(false, _private_key, _common_name, _csr_path), do: :ok

  defp maybe_write_csr(true, private_key, common_name, csr_path) do
    shell_info("Generating CSR for '#{common_name}'...")
    csr_pem = build_csr_pem(private_key, common_name)

    if csr_pem != "" do
      File.write!(csr_path, csr_pem)
      shell_info("  ✓ CSR written to #{csr_path}")
    end
  end

  defp write_gitignore(dir) do
    gitignore_path = Path.join(dir, ".gitignore")

    unless File.exists?(gitignore_path) do
      File.write!(gitignore_path, "*.pem\n*.key\n*.csr\n")
      shell_info("  ✓ .gitignore added to #{dir}")
    end
  end

  defp print_next_steps(private_path, generate_csr, csr_path, common_name) do
    shell_info("")
    shell_info("Done! Next steps:")
    shell_info("")

    if generate_csr do
      shell_info("  1. Upload #{csr_path} to the ClearBank Portal:")
      shell_info("     Institution > Certificates and Tokens > Generate API Token")
      shell_info("  2. Copy the API token (shown once only)")
    else
      shell_info(
        "  1. Generate a CSR: mix clearbank.gen.keys --csr --common-name \"#{common_name}\""
      )

      shell_info(
        "  2. Upload the CSR to: Institution > Certificates and Tokens > Generate API Token"
      )
    end

    shell_info("")
    shell_info("  Configure in config/runtime.exs:")
    shell_info("")
    shell_info("    config :clearbank,")
    shell_info("      api_token: System.fetch_env!(\"CLEARBANK_API_TOKEN\"),")
    shell_info("      private_key_path: \"#{private_path}\"")
    shell_info("")
    shell_info("  Never commit #{private_path} to version control.")
  end

  defp build_csr_pem(private_key, common_name) do
    {:RSAPrivateKey, _, modulus, pub_exp, _, _, _, _, _, _, _} = private_key
    public_key = {:RSAPublicKey, modulus, pub_exp}

    subject_rdn =
      {:rdnSequence,
       [
         [
           {:AttributeTypeAndValue, {2, 5, 4, 3},
            {:utf8String, :unicode.characters_to_binary(common_name)}}
         ]
       ]}

    pub_key_der = :public_key.der_encode(:RSAPublicKey, public_key)

    pub_key_info =
      {:SubjectPublicKeyInfo,
       {:AlgorithmIdentifier, {1, 2, 840, 113_549, 1, 1, 1}, {:asn1_OPENTYPE, <<5, 0>>}},
       pub_key_der}

    cert_req_info = {:CertificationRequestInfo, :v1, subject_rdn, pub_key_info, []}
    tbs_der = :public_key.der_encode(:CertificationRequestInfo, cert_req_info)
    signature = :public_key.sign(tbs_der, :sha256, private_key)

    csr =
      {:CertificationRequest, cert_req_info,
       {:AlgorithmIdentifier, {1, 2, 840, 113_549, 1, 1, 11}, {:asn1_OPENTYPE, <<5, 0>>}},
       signature}

    csr_der = :public_key.der_encode(:CertificationRequest, csr)

    lines =
      csr_der
      |> Base.encode64(padding: true)
      |> String.graphemes()
      |> Enum.chunk_every(64)
      |> Enum.map_join("\n", &Enum.join/1)

    "-----BEGIN CERTIFICATE REQUEST-----\n#{lines}\n-----END CERTIFICATE REQUEST-----\n"
  rescue
    e ->
      shell_error("CSR generation failed: #{inspect(e)}")

      shell_info(
        "Tip: Generate CSR manually with:\n" <>
          "  openssl req -new -key private_key.pem -out clearbank.csr"
      )

      ""
  end

  # Thin wrappers so Dialyzer sees concrete calls to IO.puts/1 in test
  # environments where Mix may not be loaded, and Mix.shell/0 in Mix env.
  # Using apply/3 avoids compile-time resolution issues when Mix is not in PLT.
  defp shell_info(msg) do
    if function_exported?(Mix, :shell, 0) do
      apply(Mix, :shell, []).info(msg)
    else
      IO.puts(msg)
    end
  end

  defp shell_error(msg) do
    if function_exported?(Mix, :shell, 0) do
      apply(Mix, :shell, []).error(msg)
    else
      IO.puts(:stderr, msg)
    end
  end

  defp raise_error(msg) do
    if function_exported?(Mix, :raise, 1) do
      apply(Mix, :raise, [msg])
    else
      raise RuntimeError, message: msg
    end
  end
end
