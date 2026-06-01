ExUnit.start()

Application.put_env(:clearbank, :api_token, "test-token")
Application.put_env(:clearbank, :environment, :simulation)
