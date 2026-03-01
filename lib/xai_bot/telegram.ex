defmodule XaiBot.Telegram do
  @moduledoc """
  Thin wrapper over the Telegram Bot API.
  """

  @max_message_length 4096

  def send_message(text, opts \\ []) do
    token = opts[:token] || Application.get_env(:xai_bot, :telegram_bot_token)
    chat_id = opts[:chat_id] || Application.get_env(:xai_bot, :telegram_chat_id)

    text
    |> split_message()
    |> Enum.reduce_while(:ok, fn chunk, _acc ->
      case do_send(token, chat_id, chunk) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp do_send(token, chat_id, text) do
    case Req.post(
           url: "https://api.telegram.org/bot:token/sendMessage",
           path_params: [token: token],
           json: %{chat_id: chat_id, text: text, parse_mode: "HTML"}
         ) do
      {:ok, %{status: 200, body: %{"ok" => true}}} ->
        {:ok, :sent}

      {:ok, %{status: status, body: body}} ->
        {:error, {:telegram_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

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
