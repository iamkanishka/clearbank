defmodule ClearBank.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/your-org/clearbank"

  def project do
    [
      app: :clearbank,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Hex
      description: description(),
      package: package(),

      # Docs
      name: "ClearBank",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),

      # Test
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.lcov": :test
      ],

      # Dialyzer
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit],
        ignore_warnings: ".dialyzer_ignore.exs",
        flags: [:error_handling, :underspecs]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {ClearBank.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # HTTP client
      {:req, "~> 0.4"},

      # JSON
      {:jason, "~> 1.4"},

      # Telemetry
      {:telemetry, "~> 1.2"},

      # Config validation
      {:nimble_options, "~> 1.0"},

      # --- Dev/Test ---
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mox, "~> 1.1", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:stream_data, "~> 0.6", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      "test.all": ["test --cover"],
      quality: ["format --check-formatted", "credo --strict", "dialyzer"],
      "quality.fix": ["format", "credo --strict"]
    ]
  end

  defp description do
    "A production-grade Elixir client for the ClearBank UK API. " <>
      "Supports GBP Accounts, GBP Payments (FPS, CHAPS, Bacs, Cheques, Cross-Border, CoP), " <>
      "Multi-currency & FX, and Embedded Banking."
  end

  defp package do
    [
      name: "clearbank",
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "ClearBank Developer Portal" => "https://clearbank.github.io/uk"
      },
      maintainers: ["Your Name"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/getting_started.md",
        "guides/webhooks.md",
        "LICENSE"
      ],
      groups_for_modules: [
        Core: [ClearBank, ClearBank.Client, ClearBank.Config],
        Auth: [ClearBank.Auth.Signer],
        HTTP: [ClearBank.HTTP, ClearBank.HTTP.Retry],
        "GBP Accounts": [
          ClearBank.Accounts,
          ClearBank.Accounts.Transactions,
          ClearBank.Accounts.BacsPaymentData,
          ClearBank.Accounts.Reporting
        ],
        "GBP Payments": [
          ClearBank.Payments.FasterPayments,
          ClearBank.Payments.InternalTransfer,
          ClearBank.Payments.Chaps,
          ClearBank.Payments.Bacs,
          ClearBank.Payments.BacsDirectDebit,
          ClearBank.Payments.Cheques,
          ClearBank.Payments.CrossBorder,
          ClearBank.Payments.ConfirmationOfPayee
        ],
        "Multi-currency & FX": [
          ClearBank.MultiCurrency.Accounts,
          ClearBank.MultiCurrency.Payments,
          ClearBank.MultiCurrency.FxTrade,
          ClearBank.MultiCurrency.FxTradeRfq,
          ClearBank.MultiCurrency.SepaCreditTransfer
        ],
        "Embedded Banking": [
          ClearBank.EmbeddedBanking.Customers,
          ClearBank.EmbeddedBanking.Accounts,
          ClearBank.EmbeddedBanking.Isa,
          ClearBank.EmbeddedBanking.Interest,
          ClearBank.EmbeddedBanking.Kyc
        ],
        "Types & Schemas": [
          ClearBank.Types,
          ClearBank.Schemas,
          ClearBank.Schemas.Account,
          ClearBank.Schemas.VirtualAccount,
          ClearBank.Schemas.Transaction,
          ClearBank.Schemas.DirectDebitInstruction,
          ClearBank.Schemas.Customer,
          ClearBank.Schemas.EmbeddedAccount,
          ClearBank.Schemas.FxQuote,
          ClearBank.Schemas.MultiCurrencyAccount,
          ClearBank.Schemas.PaginatedResponse,
          ClearBank.Error
        ],
        Webhooks: [
          ClearBank.Webhook,
          ClearBank.Webhook.Handler,
          ClearBank.Webhook.Verifier,
          ClearBank.Webhook.Events
        ],
        "Mix Tasks": [
          Mix.Tasks.Clearbank.Gen.Keys
        ],
        "Test Utilities": [
          ClearBank.TestEndpoints
        ]
      ]
    ]
  end
end
