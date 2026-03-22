defmodule XaiBot.Telegraph do
  @moduledoc """
  Publishes digest pages to Telegraph.
  """

  require Logger

  @api_url "https://api.telegra.ph/createPage"

  def publish(messages) do
    token = Application.get_env(:xai_bot, :telegraph_token)

    if is_nil(token) || token == "" do
      Logger.warning("Telegraph not configured")
      {:error, :not_configured}
    else
      content = build_content(messages)
      today = Date.utc_today() |> Date.to_string()

      body =
        Jason.encode!(%{
          access_token: token,
          title: "AI News Digest — #{today}",
          author_name: "AI News Digest",
          content: content
        })

      case System.cmd("curl", ["-s", "-X", "POST", "-H", "Content-Type: application/json", "-d", body, @api_url],
             stderr_to_stdout: true
           ) do
        {out, 0} ->
          case Jason.decode(out) do
            {:ok, %{"ok" => true, "result" => %{"url" => url}}} ->
              {:ok, url}

            {:ok, %{"ok" => false, "error" => error}} ->
              Logger.error("Telegraph error: #{error}")
              {:error, error}

            _ ->
              Logger.error("Telegraph unexpected response: #{String.slice(out, 0, 200)}")
              {:error, :bad_response}
          end

        {out, code} ->
          Logger.error("Telegraph curl failed (#{code}): #{String.slice(out, 0, 200)}")
          {:error, {:curl_failed, code}}
      end
    end
  end

  defp build_content(messages) do
    Enum.flat_map(messages, fn msg ->
      lines = String.split(msg, "\n")

      items =
        Enum.flat_map(lines, fn line ->
          cond do
            String.starts_with?(line, "<b>") ->
              text = String.replace(line, ~r/<\/?b>/, "")
              [%{tag: "h3", children: [text]}]

            String.contains?(line, "<a href=") ->
              case Regex.run(~r/href="([^"]+)"/, line) do
                [_, href] ->
                  text = String.replace(line, ~r/<[^>]+>/, "")
                  [%{tag: "p", children: [%{tag: "a", attrs: %{href: href}, children: [text]}]}]

                _ ->
                  [%{tag: "p", children: [String.replace(line, ~r/<[^>]+>/, "")]}]
              end

            String.starts_with?(line, "🔗") ->
              url = String.replace(line, "🔗 ", "")
              [%{tag: "p", children: [%{tag: "a", attrs: %{href: url}, children: ["🔗 " <> url]}]}]

            line == "" ->
              []

            true ->
              [%{tag: "p", children: [line]}]
          end
        end)

      items ++ [%{tag: "hr"}]
    end)
  end
end
