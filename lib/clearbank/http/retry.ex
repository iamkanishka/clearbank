defmodule ClearBank.HTTP.Retry do
  @moduledoc """
  Exponential backoff retry logic for ClearBank API calls.

  ClearBank's documentation states:
  - **5XX errors** are safe to retry using the **exact same `X-Request-Id` and payload**.
  - **429** (rate limited): back off and retry.
  - **409** (duplicate `X-Request-Id`): do NOT retry.

  ## Usage

      import ClearBank.HTTP.Retry

      {:ok, result} = with_retry(fn ->
        ClearBank.Payments.FasterPayments.send(client, payment)
      end)

      {:ok, result} = with_retry(
        fn -> ClearBank.Accounts.list(client) end,
        max_attempts: 5,
        base_delay_ms: 500,
        max_delay_ms: 30_000
      )

  ## Important: idempotency

  When retrying mutating requests (POST/PUT/PATCH), pass a stable `:request_id`
  so ClearBank's idempotency guarantee is preserved across retries:

      stable_id = ClearBank.HTTP.generate_request_id()

      with_retry(fn ->
        ClearBank.HTTP.post(client, "/v3/Payments/FPS", body, request_id: stable_id)
      end)
  """

  alias ClearBank.Error
  require Logger

  @default_opts [
    max_attempts: 3,
    base_delay_ms: 1_000,
    max_delay_ms: 30_000,
    jitter: true
  ]

  @type retry_opts :: [
          max_attempts: pos_integer(),
          base_delay_ms: non_neg_integer(),
          max_delay_ms: non_neg_integer(),
          jitter: boolean()
        ]

  @doc """
  Executes `fun` with automatic exponential-backoff retries on retryable errors.

  Returns `{:ok, result}` on success, or `{:error, %ClearBank.Error{}}` after
  all attempts are exhausted.

  ## Options

    * `:max_attempts` - total attempts including the first (default: `3`)
    * `:base_delay_ms` - initial backoff delay in ms (default: `1_000`)
    * `:max_delay_ms` - maximum delay cap in ms (default: `30_000`)
    * `:jitter` - add random jitter to delays to avoid thundering herd (default: `true`)

  ## Examples

      {:ok, accounts} = ClearBank.HTTP.Retry.with_retry(fn ->
        ClearBank.Accounts.list(client)
      end)

      {:ok, _} = ClearBank.HTTP.Retry.with_retry(
        fn -> ClearBank.Accounts.list(client) end,
        max_attempts: 5,
        base_delay_ms: 200
      )
  """
  @spec with_retry(fun(), retry_opts()) :: {:ok, term()} | {:error, Error.t()}
  def with_retry(fun, opts \\ []) when is_function(fun, 0) do
    opts = Keyword.merge(@default_opts, opts)
    do_retry(fun, opts, 1)
  end

  # ---

  defp do_retry(fun, opts, attempt) do
    case fun.() do
      {:ok, _} = success ->
        success

      {:error, %Error{} = error} = failure ->
        max_attempts = Keyword.fetch!(opts, :max_attempts)
        should_retry = Error.retryable?(error) and attempt < max_attempts

        if should_retry do
          retry_with_backoff(fun, opts, attempt, max_attempts, error)
        else
          log_final_failure(attempt, error)
          failure
        end
    end
  end

  defp retry_with_backoff(fun, opts, attempt, max_attempts, error) do
    delay = compute_delay(attempt, opts)

    Logger.warning(
      "[ClearBank] Retryable error (attempt #{attempt}/#{max_attempts}), " <>
        "status=#{error.status}, retrying in #{delay}ms. " <>
        "correlation_id=#{inspect(error.correlation_id)}"
    )

    Process.sleep(delay)
    do_retry(fun, opts, attempt + 1)
  end

  defp log_final_failure(attempt, error) when attempt > 1 do
    Logger.error("[ClearBank] Giving up after #{attempt} attempts. Last error: #{inspect(error)}")
  end

  defp log_final_failure(_attempt, _error), do: :ok

  defp compute_delay(attempt, opts) do
    base = Keyword.fetch!(opts, :base_delay_ms)
    max_delay = Keyword.fetch!(opts, :max_delay_ms)
    use_jitter = Keyword.fetch!(opts, :jitter)

    exponential = min(base * Integer.pow(2, attempt - 1), max_delay)

    if use_jitter do
      :rand.uniform(exponential + 1) - 1
    else
      exponential
    end
  end
end
