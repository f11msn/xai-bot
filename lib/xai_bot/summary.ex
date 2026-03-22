defmodule XaiBot.Summary do
  @moduledoc """
  Generates a Russian-language summary of the digest via OpenRouter (DeepSeek V3.2).
  """

  require Logger

  @api_url "https://openrouter.ai/api/v1/chat/completions"
  @model "deepseek/deepseek-v3.2"

  @summary_prompt """
  Ты — редактор AI-новостного Telegram-канала на русском языке. \
  Тебе дают дайджест новостей за последние часы, разбитый по категориям.

  Начни с одной цепляющей фразы, резюмирующей главное событие. \
  Затем кратко опиши 3-5 ключевых событий. \
  Пиши только на русском языке. Технические названия (модели, фреймворки) оставь на английском. \
  Стиль: информативный, живой, без воды, без приветствий. \
  Формат: plain text. Без markdown, без звёздочек, без HTML-тегов. \
  Пиши только фактами из дайджеста, не додумывай.
  """

  def generate(digest) when is_map(digest) do
    with {:ok, api_key} <- get_config(),
         content when not is_nil(content) <- build_prompt_content(digest) do
      call_llm(api_key, @summary_prompt, content, 0.3)
    else
      nil ->
        Logger.info("No items for summary")
        {:error, :empty}

      error ->
        error
    end
  end

  defp get_config do
    api_key = Application.get_env(:xai_bot, :openrouter_api_key)

    if is_nil(api_key) || api_key == "" do
      Logger.warning("OpenRouter not configured")
      {:error, :not_configured}
    else
      {:ok, api_key}
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

  defp call_llm(api_key, system_prompt, content, temperature) do
    body = %{
      model: @model,
      temperature: temperature,
      messages: [
        %{role: "system", content: system_prompt},
        %{role: "user", content: content}
      ]
    }

    case Req.post(
           url: @api_url,
           json: body,
           headers: [{"Authorization", "Bearer #{api_key}"}],
           receive_timeout: 60_000
         ) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => text}} | _]}}} ->
        {:ok, strip_code_fences(text)}

      {:ok, %{status: status, body: body}} ->
        Logger.error("OpenRouter error: #{status} #{inspect(body)}")
        {:error, {:llm_error, status}}

      {:error, reason} ->
        Logger.error("OpenRouter request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp strip_code_fences(text) do
    text
    |> String.replace(~r/\A```\w*\n/, "")
    |> String.replace(~r/\n```\z/, "")
  end
end
