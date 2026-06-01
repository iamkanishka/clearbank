defmodule ClearBank.Client do
  @moduledoc """
  Immutable client struct holding credentials and configuration.

  Create with `ClearBank.new/1` or `ClearBank.Config.default_client/0`.
  """

  alias ClearBank.Config

  @enforce_keys [:api_token, :base_url, :timeout, :telemetry_prefix]
  defstruct [
    :api_token,
    :private_key,
    :base_url,
    :timeout,
    :telemetry_prefix,
    pool_size: 10
  ]

  @type t :: %__MODULE__{
          api_token: String.t(),
          private_key: binary() | nil,
          base_url: String.t(),
          timeout: non_neg_integer(),
          telemetry_prefix: [atom()],
          pool_size: pos_integer()
        }

  @doc """
  Builds a new `%Client{}` from keyword options.
  See `ClearBank.Config.schema/0` for all options.
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    validated = NimbleOptions.validate!(opts, Config.schema())

    env = Keyword.get(validated, :environment, :simulation)
    base_url = Keyword.get(validated, :base_url, Config.base_url(env))
    private_key = Config.resolve_private_key(validated)

    %__MODULE__{
      api_token: Keyword.fetch!(validated, :api_token),
      private_key: private_key,
      base_url: base_url,
      timeout: Keyword.get(validated, :timeout, 30_000),
      pool_size: Keyword.get(validated, :pool_size, 10),
      telemetry_prefix: Keyword.get(validated, :telemetry_prefix, [:clearbank])
    }
  end
end
