defmodule ClearBank.Accounts.Reporting do
  @moduledoc """
  Account reporting via camt.053 bank statements.

  ClearBank generates ISO 20022 camt.053 statement files on request.
  Statements are paginated — request generation, then retrieve page-by-page.

  ## Workflow

  1. Call `request_statement/2` with your date range and account.
  2. The response includes a `messageId`.
  3. Poll `get_statement_page/3` with the `messageId` and page numbers
     until you have all pages (check `totalPages` in the response).

  ## Examples

      {:ok, %{"messageId" => msg_id}} = ClearBank.Accounts.Reporting.request_statement(client,
        account_id: "acct-uuid",
        start_date: "2024-01-01",
        end_date: "2024-01-31"
      )

      {:ok, page} = ClearBank.Accounts.Reporting.get_statement_page(client, msg_id, 1)
  """

  alias ClearBank.{Client, HTTP}

  @doc """
  Requests generation of a camt.053 statement.

  ## Required params

    * `:account_id` - the real account UUID
    * `:start_date` - ISO 8601 date string, e.g. `"2024-01-01"`
    * `:end_date` - ISO 8601 date string, e.g. `"2024-01-31"`

  ## Optional params

    * `:currency` - ISO 4217 code (default: `"GBP"`)
    * `:include_virtual` - boolean, include virtual account transactions

  ## Examples

      {:ok, resp} = ClearBank.Accounts.Reporting.request_statement(client,
        account_id: "acct-uuid",
        start_date: "2024-01-01",
        end_date: "2024-01-31",
        currency: "GBP"
      )
  """
  @spec request_statement(Client.t(), keyword()) :: HTTP.result()
  def request_statement(%Client{} = client, params) do
    body = %{
      "accountId" => Keyword.fetch!(params, :account_id),
      "startDate" => Keyword.fetch!(params, :start_date),
      "endDate" => Keyword.fetch!(params, :end_date),
      "currency" => Keyword.get(params, :currency, "GBP"),
      "includeVirtualAccounts" => Keyword.get(params, :include_virtual, false)
    }

    HTTP.post(client, "/v1/statementrequests", body)
  end

  @doc """
  Downloads a specific page of a generated camt.053 statement.

  ## Examples

      {:ok, page_data} = ClearBank.Accounts.Reporting.get_statement_page(client, "msg-uuid", 1)
  """
  @spec get_statement_page(Client.t(), String.t(), pos_integer()) :: HTTP.result()
  def get_statement_page(%Client{} = client, message_id, page_number)
      when is_binary(message_id) and is_integer(page_number) and page_number >= 1 do
    HTTP.get(client, "/v1/statementrequests/#{message_id}/pages/#{page_number}")
  end

  @doc """
  Fetches all pages of a statement and returns them as a list.

  Makes sequential HTTP calls until all pages are retrieved.
  For large statements, consider streaming page-by-page instead.

  ## Examples

      {:ok, all_pages} = ClearBank.Accounts.Reporting.get_all_pages(client, "msg-uuid")
  """
  @spec get_all_pages(Client.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def get_all_pages(%Client{} = client, message_id) do
    with {:ok, first_page} <- get_statement_page(client, message_id, 1) do
      total_pages = get_in(first_page, ["totalPages"]) || 1
      collect_remaining_pages(client, message_id, first_page, total_pages)
    end
  end

  # ---

  defp collect_remaining_pages(_client, _message_id, first_page, 1) do
    {:ok, [first_page]}
  end

  defp collect_remaining_pages(client, message_id, first_page, total_pages) do
    pages =
      Enum.reduce_while(2..total_pages, [first_page], fn page_num, acc ->
        case get_statement_page(client, message_id, page_num) do
          {:ok, page} -> {:cont, acc ++ [page]}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case pages do
      all_pages when is_list(all_pages) -> {:ok, all_pages}
      err -> err
    end
  end
end
