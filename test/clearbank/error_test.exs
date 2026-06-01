defmodule ClearBank.ErrorTest do
  use ExUnit.Case, async: true

  alias ClearBank.Error

  describe "from_response/2" do
    test "parses title+errors response (validation error style)" do
      resp = %Req.Response{
        status: 400,
        headers: [],
        body: %{"title" => "Validation failed", "errors" => %{"amount" => ["is required"]}}
      }

      error = Error.from_response(resp)

      assert error.status == 400
      assert error.message == "Validation failed"
      assert error.details == %{"amount" => ["is required"]}
    end

    test "parses title+detail response (RFC 7807 style)" do
      resp = %Req.Response{
        status: 422,
        headers: [],
        body: %{"title" => "Unprocessable", "detail" => "Amount exceeds limit"}
      }

      error = Error.from_response(resp)
      assert error.status == 422
      assert error.message =~ "Amount exceeds limit"
    end

    test "parses message response" do
      resp = %Req.Response{
        status: 409,
        headers: [],
        body: %{"message" => "Duplicate X-Request-Id"}
      }

      error = Error.from_response(resp)
      assert error.status == 409
      assert error.message == "Duplicate X-Request-Id"
    end

    test "captures X-Correlation-Id header" do
      resp = %Req.Response{
        status: 500,
        headers: [{"x-correlation-id", "corr-abc-123"}],
        body: %{"message" => "Internal error"}
      }

      error = Error.from_response(resp, "req-123")
      assert error.correlation_id == "corr-abc-123"
      assert error.request_id == "req-123"
    end

    test "handles unexpected body shape gracefully" do
      resp = %Req.Response{status: 503, headers: [], body: "Service Unavailable"}
      error = Error.from_response(resp)
      assert error.status == 503
      assert error.message =~ "HTTP 503"
    end
  end

  describe "retryable?/1" do
    test "returns true for 429" do
      assert Error.retryable?(%Error{status: 429, message: "rate limited"})
    end

    test "returns true for 500" do
      assert Error.retryable?(%Error{status: 500, message: "server error"})
    end

    test "returns true for 503" do
      assert Error.retryable?(%Error{status: 503, message: "unavailable"})
    end

    test "returns false for 400" do
      refute Error.retryable?(%Error{status: 400, message: "bad request"})
    end

    test "returns false for 409" do
      refute Error.retryable?(%Error{status: 409, message: "conflict"})
    end
  end

  describe "Exception.message/1" do
    test "formats message with status and correlation ID" do
      err = %Error{status: 400, message: "Bad", correlation_id: "corr-1"}
      assert Exception.message(err) =~ "400"
      assert Exception.message(err) =~ "corr-1"
    end

    test "formats message without correlation ID" do
      err = %Error{status: 401, message: "Unauthorized", correlation_id: nil}
      msg = Exception.message(err)
      assert msg =~ "401"
      refute msg =~ "X-Correlation-Id"
    end
  end
end
