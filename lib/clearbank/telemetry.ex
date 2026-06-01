defmodule ClearBank.Telemetry do
  @moduledoc """
  Telemetry integration for `clearbank`.

  ## Events

  All events are prefixed by the configured `:telemetry_prefix` (default `[:clearbank]`).

  | Event | When | Measurements | Metadata |
  |---|---|---|---|
  | `[:clearbank, :request, :start]` | Before HTTP call | `%{system_time: integer}` | `%{method, url, request_id}` |
  | `[:clearbank, :request, :stop]` | After successful response | `%{duration: integer}` | `%{method, url, request_id}` |
  | `[:clearbank, :request, :exception]` | On exception | `%{duration: integer}` | `%{method, url, request_id, error}` |

  ## Attaching handlers

      :telemetry.attach_many(
        "clearbank-logger",
        [
          [:clearbank, :request, :start],
          [:clearbank, :request, :stop],
          [:clearbank, :request, :exception]
        ],
        &MyApp.Telemetry.handle_clearbank/4,
        nil
      )

  """

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl GenServer
  @spec init(term()) :: {:ok, %{}}
  def init(_opts), do: {:ok, %{}}

  @doc false
  @spec start([atom()], map()) :: integer()
  def start(prefix, metadata) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      prefix ++ [:request, :start],
      %{system_time: System.system_time()},
      metadata
    )

    start_time
  end

  @doc false
  # :telemetry.execute/3 always returns :ok; we return its value directly.
  @spec stop([atom()], integer(), map(), {:ok, term()} | {:error, term()}) :: :ok
  def stop(prefix, start_time, metadata, result) do
    duration = System.monotonic_time() - start_time

    case result do
      {:ok, _} ->
        :telemetry.execute(prefix ++ [:request, :stop], %{duration: duration}, metadata)

      {:error, error} ->
        :telemetry.execute(
          prefix ++ [:request, :exception],
          %{duration: duration},
          Map.put(metadata, :error, error)
        )
    end
  end
end
