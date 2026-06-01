defmodule ClearBank.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {ClearBank.RateLimiter, []},
      {ClearBank.Telemetry, []}
    ]

    opts = [strategy: :one_for_one, name: ClearBank.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
