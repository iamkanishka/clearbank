defmodule ClearBank.Config do
  @moduledoc """
  Configuration management for `clearbank`.

  Reads from `Application.get_env/2` and validates with `NimbleOptions`.
  """

  alias ClearBank.Client

  @schema NimbleOptions.new!(
            api_token: [
              type: :string,
              required: true,
              doc: "ClearBank API bearer token from the Portal."
            ],
            private_key: [
              type: :string,
              doc: "RSA private key PEM binary. Required for POST/PATCH/PUT requests."
            ],
            private_key_path: [
              type: :string,
              doc: "Path to RSA private key PEM file. Alternative to :private_key."
            ],
            environment: [
              type: {:in, [:simulation, :production]},
              default: :simulation,
              doc: "API environment. `:simulation` or `:production`."
            ],
            timeout: [
              type: :non_neg_integer,
              default: 30_000,
              doc: "HTTP request timeout in milliseconds."
            ],
            pool_size: [
              type: :pos_integer,
              default: 10,
              doc: "HTTP connection pool size."
            ],
            base_url: [
              type: :string,
              doc: "Override the base URL. Useful for testing."
            ],
            telemetry_prefix: [
              type: {:list, :atom},
              default: [:clearbank],
              doc: "Prefix for Telemetry events."
            ]
          )

  @simulation_url "https://institution-api-sim.clearbank.co.uk"
  @production_url "https://institution-api.clearbank.co.uk"

  @doc """
  Returns the NimbleOptions schema for introspection and documentation.
  """
  @spec schema() :: NimbleOptions.t()
  def schema, do: @schema

  @doc """
  Validates and returns application config as a keyword list.
  Raises `NimbleOptions.ValidationError` on invalid config.
  """
  @spec fetch!() :: keyword()
  def fetch! do
    raw = Application.get_all_env(:clearbank)
    NimbleOptions.validate!(raw, @schema)
  end

  @doc """
  Builds the default `ClearBank.Client` from application config.
  """
  @spec default_client() :: Client.t()
  def default_client do
    opts = fetch!()
    Client.new(opts)
  end

  @doc """
  Returns the base URL for the given environment.
  """
  @spec base_url(:simulation | :production) :: String.t()
  def base_url(:simulation), do: @simulation_url
  def base_url(:production), do: @production_url

  @doc """
  Resolves the private key binary from either `:private_key` or `:private_key_path`.
  """
  @spec resolve_private_key(keyword()) :: binary() | nil
  def resolve_private_key(opts) do
    cond do
      key = Keyword.get(opts, :private_key) -> key
      path = Keyword.get(opts, :private_key_path) -> File.read!(path)
      true -> nil
    end
  end
end
