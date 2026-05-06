defmodule HexPlayground.HTTP do
  @moduledoc false

  def get!(url, opts \\ []) do
    retry = Keyword.get(opts, :retry, 3)
    timeout = Keyword.get(opts, :timeout, 120_000)

    request = [url: url, receive_timeout: timeout, retry: false]

    request =
      if into = Keyword.get(opts, :into), do: Keyword.put(request, :into, into), else: request

    do_get!(request, retry)
  end

  defp do_get!(request, attempts_left) do
    response = Req.get!(request)

    case response.status do
      status when status in 200..299 ->
        response

      status when attempts_left > 0 and status in [408, 429, 500, 502, 503, 504] ->
        Process.sleep(backoff(attempts_left))
        do_get!(request, attempts_left - 1)

      status ->
        raise "GET #{request[:url]} failed with #{status}: #{inspect(response.body)}"
    end
  rescue
    error in [Req.TransportError, Mint.TransportError, Mint.HTTPError] ->
      if attempts_left > 0 do
        Process.sleep(backoff(attempts_left))
        do_get!(request, attempts_left - 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp backoff(attempts_left), do: (4 - attempts_left) * 500
end
