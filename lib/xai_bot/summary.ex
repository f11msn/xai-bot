defmodule XaiBot.Summary do
  @moduledoc """
  Translates digest messages and generates a Russian-language summary via YandexGPT.
  """

  require Logger

  @api_url "https://llm.api.cloud.yandex.net/foundationModels/v1/completion"

  @summary_prompt """
  Ты — редактор AI-новостного Telegram-канала. Тебе дают дайджест новостей за последние часы, \
  разбитый по категориям: Papers, Releases, Tools, Insights.

  Напиши краткую сводку на русском языке для читателей канала. \
  Выдели самое важное и интересное — 3-5 ключевых событий. \
  Стиль: информативный, без воды, без приветствий. \
  Формат: plain text, без HTML-тегов, без markdown.
  """

  def generate(digest) when is_map(digest) do
    with {:ok, api_key, folder_id} <- get_config(),
         content when not is_nil(content) <- build_prompt_content(digest) do
      call_llm(api_key, folder_id, @summary_prompt, content, 0.3)
    else
      nil ->
        Logger.info("No items for summary")
        {:error, :empty}

      error ->
        error
    end
  end

  defp get_config do
    api_key = Application.get_env(:xai_bot, :yc_llm_api_key)
    folder_id = Application.get_env(:xai_bot, :yc_folder_id)

    if is_nil(api_key) || api_key == "" || is_nil(folder_id) || folder_id == "" do
      Logger.warning("YandexGPT not configured")
      {:error, :not_configured}
    else
      {:ok, api_key, folder_id}
    end
  end

  defp build_prompt_content(digest) do
    sections =
      [:papers, :releases, :tools, :insights]
      |> Enum.map(fn category ->
        items = Map.get(digest, category, [])

        if items != [] do
          header = category |> Atom.to_string() |> String.capitalize()
          entries = Enum.map_join(items, "\n", fn item -> "- #{item.text}" end)
          "#{header}:\n#{entries}"
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    if sections == "", do: nil, else: sections
  end

  defp call_llm(api_key, folder_id, system_prompt, content, temperature) do
    body = %{
      modelUri: "gpt://#{folder_id}/yandexgpt-lite/latest",
      completionOptions: %{temperature: temperature, stream: false},
      messages: [
        %{role: "system", text: system_prompt},
        %{role: "user", text: content}
      ]
    }

    case Req.post(url: @api_url, json: body, headers: [{"Authorization", "Bearer #{api_key}"}], receive_timeout: 60_000) do
      {:ok, %{status: 200, body: %{"result" => %{"alternatives" => [%{"message" => %{"text" => text}} | _]}}}} ->
        {:ok, strip_code_fences(text)}

      {:ok, %{status: status, body: body}} ->
        Logger.error("YandexGPT error: #{status} #{inspect(body)}")
        {:error, {:llm_error, status}}

      {:error, reason} ->
        Logger.error("YandexGPT request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp strip_code_fences(text) do
    text
    |> String.replace(~r/\A```\w*\n/, "")
    |> String.replace(~r/\n```\z/, "")
  end
end
