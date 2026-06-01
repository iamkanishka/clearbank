defmodule ClearBank.ConfigTest do
  use ExUnit.Case, async: true

  alias ClearBank.Config

  describe "base_url/1" do
    test "returns simulation URL" do
      assert Config.base_url(:simulation) =~ "sim"
    end

    test "returns production URL" do
      url = Config.base_url(:production)
      refute url =~ "sim"
      assert url =~ "clearbank"
    end
  end

  describe "resolve_private_key/1" do
    test "returns :private_key value when present" do
      assert Config.resolve_private_key(private_key: "my-pem") == "my-pem"
    end

    test "returns nil when neither key option is set" do
      assert Config.resolve_private_key([]) == nil
    end

    test "reads file when :private_key_path is set" do
      path = Path.join(System.tmp_dir!(), "test_private_key_#{System.unique_integer()}.pem")
      File.write!(path, "pem-contents")

      assert Config.resolve_private_key(private_key_path: path) == "pem-contents"
      File.rm!(path)
    end
  end
end

defmodule ClearBank.ClientTest do
  use ExUnit.Case, async: true

  alias ClearBank.{Client, TestSupport}

  describe "new/1" do
    test "builds a client struct with valid options" do
      {priv, _pub} = TestSupport.generate_key_pair()

      client = Client.new(api_token: "tok_test", private_key: priv, environment: :simulation)

      assert %Client{} = client
      assert client.api_token == "tok_test"
      assert client.private_key == priv
      assert client.base_url =~ "sim"
      assert client.timeout == 30_000
    end

    test "uses production URL for :production environment" do
      client = Client.new(api_token: "tok_prod", environment: :production)
      refute client.base_url =~ "sim"
    end

    test "allows base_url override" do
      client = Client.new(api_token: "tok", base_url: "http://localhost:4000")
      assert client.base_url == "http://localhost:4000"
    end

    test "raises for missing :api_token" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Client.new(environment: :simulation)
      end
    end

    test "raises for invalid :environment" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Client.new(api_token: "tok", environment: :invalid)
      end
    end

    test "sets default timeout of 30_000" do
      client = Client.new(api_token: "tok")
      assert client.timeout == 30_000
    end

    test "accepts custom timeout" do
      client = Client.new(api_token: "tok", timeout: 60_000)
      assert client.timeout == 60_000
    end
  end
end
