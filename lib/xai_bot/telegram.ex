defmodule XaiBot.Telegram do
  @moduledoc """
  Thin wrapper over the Telegram Bot API.
  Sends to all configured destinations via curl (SOCKS5 proxy support).
  """

  require Logger

  @base_url "https://api.telegram.org"
  @max_message_length 4096

  def send_message(text) do
    token = Application.get_env(:xai_bot, :telegram_bot_token)
    destinations = Application.get_env(:xai_bot, :telegram_destinations, [])

    Enum.each(destinations, fn dest ->
      split_message(text)
      |> Enum.each(fn chunk ->
        case do_send(token, dest, chunk) do
          {:ok, _} -> :ok
          {:error, reason} ->
            Logger.warning("Failed to send to #{dest.chat_id}: #{inspect(reason)}")
        end
      end)
    end)

    :ok
  end

  defp do_send(token, dest, text) do
    body =
      %{chat_id: dest.chat_id, text: text, parse_mode: "HTML"}
      |> maybe_put(:message_thread_id, dest[:thread_id])

    json = Jason.encode!(body)
    proxy = Application.get_env(:xai_bot, :telegram_proxy)

    proxy_args =
      if proxy && proxy != "" do
        ["--socks5-hostname", proxy]
      else
        []
      end

    args =
      ["-s", "--max-time", "15"] ++
        proxy_args ++
        ["-H", "Content-Type: application/json", "-d", json,
         "#{@base_url}/bot#{token}/sendMessage"]

    case System.cmd("curl", args, stderr_to_stdout: true) do
      {out, 0} ->
        if String.contains?(out, "\"ok\":true"),
          do: {:ok, :sent},
          else: {:error, out}

      {out, code} ->
        {:error, {:curl_failed, code, String.slice(out, 0, 200)}}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  def split_message(text) when byte_size(text) <= @max_message_length, do: [text]

  def split_message(text) do
    text
    |> String.split("\n\n")
    |> Enum.reduce([""], fn paragraph, [current | rest] ->
      candidate = if current == "", do: paragraph, else: current <> "\n\n" <> paragraph

      if byte_size(candidate) <= @max_message_length do
        [candidate | rest]
      else
        [paragraph, current | rest]
      end
    end)
    |> Enum.reverse()
    |> Enum.reject(&(&1 == ""))
  end
end
