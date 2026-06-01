defmodule ClearBank.RateLimiter do
  @moduledoc """
  Minimal token-bucket rate limiter backed by a GenServer.

  ClearBank returns `429` responses when rate limits are exceeded.
  This module provides a lightweight client-side guard you can opt into
  by calling `ClearBank.RateLimiter.check_rate/1` in your application layer.

  Limits are dynamic per ClearBank's docs and significantly lower in simulation.
  You should always handle `429` responses from the server regardless.
  """

  use GenServer

  @default_rps 50
  @window_ms 1_000

  defstruct [:rps, :window_ms, :tokens, :last_refill]

  # --- Public API ---

  def start_link(opts) do
    rps = Keyword.get(opts, :rps, @default_rps)
    GenServer.start_link(__MODULE__, %{rps: rps}, name: __MODULE__)
  end

  @doc """
  Checks and consumes a rate-limit token. Returns `:ok` or `{:error, :rate_limited}`.
  """
  @spec check_rate(pos_integer()) :: :ok | {:error, :rate_limited}
  def check_rate(cost \\ 1) do
    GenServer.call(__MODULE__, {:check_rate, cost})
  end

  # --- GenServer ---

  @impl GenServer
  def init(%{rps: rps}) do
    state = %__MODULE__{
      rps: rps,
      window_ms: @window_ms,
      tokens: rps,
      last_refill: System.monotonic_time(:millisecond)
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:check_rate, cost}, _from, state) do
    state = refill(state)

    if state.tokens >= cost do
      {:reply, :ok, %{state | tokens: state.tokens - cost}}
    else
      {:reply, {:error, :rate_limited}, state}
    end
  end

  defp refill(%__MODULE__{} = state) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - state.last_refill
    new_tokens = min(state.rps, state.tokens + elapsed * state.rps / state.window_ms)
    %{state | tokens: new_tokens, last_refill: now}
  end
end
