defmodule XaiBot.Anubis do
  @moduledoc """
  Solves Anubis anti-bot challenges programmatically.

  Anubis "preact" challenge: SHA256(random_data) + minimum wait time.
  On success, returns a JWT cookie valid for ~7 days.
  """

  require Logger

  @cookie_filename "anubis_cookie"

  def load_cookie do
    case File.read(cookie_path()) do
      {:ok, cookie} ->
        cookie = String.trim(cookie)
        if cookie != "", do: cookie, else: nil

      {:error, _} ->
        nil
    end
  end

  def save_cookie(cookie) do
    File.mkdir_p!(Path.dirname(cookie_path()))
    File.write!(cookie_path(), cookie)
  end

  def solve(challenge_html, base_url, proxy) do
    with {:ok, info} <- parse_challenge(challenge_html),
         result = sha256_hex(info.challenge),
         :ok <- wait_for_difficulty(info.difficulty),
         {:ok, cookie} <- submit_solution(base_url, info.redir, result, info.challenge_id, proxy) do
      save_cookie(cookie)
      Logger.info("Anubis challenge solved, cookie saved")
      {:ok, cookie}
    end
  end

  defp parse_challenge(html) do
    with {:ok, preact_json} <- extract_json(html, "preact_info"),
         {:ok, anubis_json} <- extract_json(html, "anubis_challenge") do
      challenge_id = get_in(anubis_json, ["challenge", "id"])

      {:ok,
       %{
         challenge: preact_json["challenge"],
         difficulty: preact_json["difficulty"],
         redir: preact_json["redir"],
         challenge_id: challenge_id
       }}
    end
  end

  defp extract_json(html, script_id) do
    pattern = ~r/<script id="#{Regex.escape(script_id)}" type="application\/json">(.*?)\n<\/script>/s

    case Regex.run(pattern, html) do
      [_, json_str] ->
        case Jason.decode(json_str) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> {:error, {:json_parse_failed, script_id}}
        end

      nil ->
        {:error, {:script_not_found, script_id}}
    end
  end

  defp sha256_hex(data) do
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  defp wait_for_difficulty(difficulty) do
    delay = difficulty * 125
    Logger.debug("Anubis: waiting #{delay}ms for difficulty #{difficulty}")
    Process.sleep(delay)
    :ok
  end

  defp submit_solution(base_url, redir_path, result, challenge_id, proxy) do
    url = "#{base_url}#{redir_path}&result=#{result}"

    case XaiBot.HTTP.get(url,
           cookies: %{"techaro.lol-anubis-cookie-verification" => challenge_id},
           proxy: proxy,
           include_headers: true
         ) do
      {:ok, headers} -> extract_cookie(headers)
      {:error, _} = err -> err
    end
  end

  defp extract_cookie(headers) do
    case Regex.run(~r/set-cookie:\s*techaro\.lol-anubis-auth=([^;]+)/i, headers) do
      [_, cookie] when cookie != "" ->
        {:ok, cookie}

      _ ->
        {:error, :cookie_not_found}
    end
  end

  defp cookie_path do
    Path.join(Application.get_env(:xai_bot, :data_dir), @cookie_filename)
  end
end
