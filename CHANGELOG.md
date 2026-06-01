# Changelog

All notable changes to `clearbank` are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

## [1.0.0] - 2026-05-30

### Added

#### Core
- `ClearBank` — top-level entrypoint and `new/1` client factory
- `ClearBank.Client` — immutable client struct with NimbleOptions validation
- `ClearBank.Config` — application config management and environment resolution
- `ClearBank.Error` — structured error type with `retryable?/1` and `Exception` behaviour
- `ClearBank.HTTP` — core request pipeline: auth headers, DigitalSignature, X-Request-Id, telemetry
- `ClearBank.Auth.Signer` — RSA-SHA256 PKCS#1 v1.5 request signing and webhook verification
- `ClearBank.Telemetry` — Telemetry events for all HTTP requests
- `ClearBank.RateLimiter` — Token-bucket client-side rate limiter GenServer
- `ClearBank.Types` — Shared type specs and query-building helpers

#### GBP Accounts
- `ClearBank.Accounts` — Real and virtual account CRUD
- `ClearBank.Accounts.Transactions` — Institution-wide, account, and virtual account transaction retrieval
- `ClearBank.Accounts.BacsPaymentData` — Direct Debit collections and returns
- `ClearBank.Accounts.Reporting` — camt.053 statement request and paginated retrieval

#### GBP Payments
- `ClearBank.Payments.FasterPayments` — Single and bulk FPS with APP scam routing control
- `ClearBank.Payments.Chaps` — CHAPS customer payments and returns (pacs.008 / pacs.004)
- `ClearBank.Payments.Bacs` — Bacs payment returns for real and virtual accounts
- `ClearBank.Payments.BacsDirectDebit` — DDI create, list, get, cancel for real and virtual accounts
- `ClearBank.Payments.Cheques` — ICS cheque image deposit
- `ClearBank.Payments.CrossBorder` — GBP cross-border payments (**deprecated**, EOL 13 Nov 2026)
- `ClearBank.Payments.ConfirmationOfPayee` — Outbound CoP name check; opt-out for real and virtual accounts

#### Multi-currency & FX
- `ClearBank.MultiCurrency.Accounts` — Multi-currency real and virtual account management and transactions
- `ClearBank.MultiCurrency.Payments` — Single/bulk international payments; batch cancel
- `ClearBank.MultiCurrency.FxTrade` — Spot FX execution
- `ClearBank.MultiCurrency.FxTradeRfq` — Request-for-quote, execute, and reject
- `ClearBank.MultiCurrency.SepaCreditTransfer` — SCT UK euro send and return

#### Embedded Banking
- `ClearBank.EmbeddedBanking.Customers` — Retail, sole trader, and legal entity onboarding
- `ClearBank.EmbeddedBanking.Accounts` — Hub, payment, and savings account creation/management
- `ClearBank.EmbeddedBanking.Isa` — Flexible Cash ISA create and transfer-in
- `ClearBank.EmbeddedBanking.Interest` — Interest product listing and account configuration
- `ClearBank.EmbeddedBanking.Kyc` — KYC status retrieval and data submission

#### Webhooks
- `ClearBank.Webhook` — Envelope struct, `parse/1`, `ack_body/1`
- `ClearBank.Webhook.Verifier` — Inbound webhook signature verification
- `ClearBank.Webhook.Handler` — Behaviour + `__using__` macro for typed webhook dispatch

#### Tooling
- Full ExUnit test suite with Bypass HTTP mocking
- GitHub Actions CI across Elixir 1.14–1.16 / OTP 25–26
- Dialyzer integration with PLT caching
- Credo strict linting
- ExCoveralls coverage reporting
- ExDoc with grouped module navigation

[Unreleased]: https://github.com/your-org/clearbank/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/your-org/clearbank/releases/tag/v0.1.0
