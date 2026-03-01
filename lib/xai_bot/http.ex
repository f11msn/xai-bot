defmodule XaiBot.HTTP do
  @moduledoc """
  HTTP client wrapping curl for SOCKS5 proxy support.
  Mint/Req don't support SOCKS5, so curl is the pragmatic choice.
  """

  @user_agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"

  def get(url, opts \\ []) do
    headers = opts[:headers] || []
    cookies = opts[:cookies] || %{}
    proxy = opts[:proxy]
    include_headers = opts[:include_headers] || false

    cookie_str =
      cookies
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join("; ")

    proxy_args =
      if proxy && proxy != "" do
        ["--proxy", "socks5h://#{proxy}"]
      else
        []
      end

    header_args =
      [{"User-Agent", @user_agent} | headers]
      |> Enum.flat_map(fn {k, v} -> ["-H", "#{k}: #{v}"] end)

    cookie_args = if cookie_str != "", do: ["-b", cookie_str], else: []

    output_args =
      if include_headers do
        ["-D", "-", "-o", "/dev/null"]
      else
        []
      end

    args =
      ["-sL", "--connect-timeout", "10", "--max-time", "30"] ++
        header_args ++ cookie_args ++ output_args ++ proxy_args ++ [url]

    case System.cmd("curl", args, stderr_to_stdout: true) do
      {body, 0} -> {:ok, body}
      {output, code} -> {:error, {:curl_failed, code, String.slice(output, 0, 200)}}
    end
  end
end
