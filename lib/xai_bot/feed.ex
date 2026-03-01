defmodule XaiBot.Feed do
  @moduledoc """
  Fetches and parses AI news from a Nitter RSS feed.
  Automatically solves Anubis challenges when cookie is expired.
  """

  import SweetXml

  require Logger

  def fetch(opts \\ []) do
    base_url = opts[:base_url] || Application.get_env(:xai_bot, :nitter_base_url)
    list_id = opts[:list_id] || Application.get_env(:xai_bot, :twitter_list_id)
    proxy = opts[:proxy] || Application.get_env(:xai_bot, :socks5_proxy)
    cookie = XaiBot.Anubis.load_cookie()

    url = "#{base_url}/i/lists/#{list_id}/rss"

    case fetch_rss(url, cookie, proxy) do
      {:ok, body} ->
        {:ok, parse_rss(body)}

      {:error, {:challenge, html}} ->
        Logger.info("Anubis challenge detected, solving...")

        with {:ok, new_cookie} <- XaiBot.Anubis.solve(html, base_url, proxy),
             {:ok, body} <- fetch_rss(url, new_cookie, proxy) do
          {:ok, parse_rss(body)}
        end

      {:error, _} = err ->
        err
    end
  end

  defp fetch_rss(url, cookie, proxy) do
    case XaiBot.HTTP.get(url,
           cookies: %{"techaro.lol-anubis-auth" => cookie},
           proxy: proxy
         ) do
      {:ok, body} ->
        cond do
          String.starts_with?(body, "<?xml") ->
            {:ok, body}

          String.contains?(body, "anubis_challenge") ->
            {:error, {:challenge, body}}

          true ->
            {:error, {:unexpected_response, String.slice(body, 0, 200)}}
        end

      {:error, _} = err ->
        err
    end
  end

  def parse_rss(xml) when is_binary(xml) do
    xml
    |> xpath(~x"//item"l,
      id: ~x"./guid/text()"s,
      title: ~x"./title/text()"s,
      author: ~x"./dc:creator/text()"s,
      description: ~x"./description/text()"s,
      published_at: ~x"./pubDate/text()"s,
      link: ~x"./link/text()"s
    )
    |> Enum.map(&normalize_item/1)
  end

  defp normalize_item(item) do
    %{
      id: item.id,
      author: String.trim_leading(item.author, "@"),
      text: strip_html(item.description),
      urls: extract_urls(item.description),
      published_at: parse_date(item.published_at),
      link: nitter_to_twitter(item.link),
      title: item.title
    }
  end

  defp strip_html(html) do
    html
    |> String.replace(~r/<br\s*\/?>/, "\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&#39;", "'")
    |> String.replace(~r/\n{2,}/, "\n")
    |> String.trim()
  end

  defp extract_urls(html) do
    ~r/href="(https?:\/\/[^"]+)"/
    |> Regex.scan(html)
    |> Enum.map(fn [_, url] -> url end)
    |> Enum.reject(&nitter_internal?/1)
  end

  defp nitter_internal?(url), do: String.contains?(url, "/pic/")

  defp nitter_to_twitter(url) do
    String.replace(url, ~r/https:\/\/[^\/]+/, "https://x.com")
    |> String.replace(~r/#m$/, "")
  end

  defp parse_date(date_str) do
    case Regex.run(
           ~r/\w+, (\d+) (\w+) (\d+) (\d+):(\d+):(\d+) GMT/,
           date_str
         ) do
      [_, day, month, year, hour, min, sec] ->
        month_num = month_to_number(month)

        NaiveDateTime.new!(
          String.to_integer(year),
          month_num,
          String.to_integer(day),
          String.to_integer(hour),
          String.to_integer(min),
          String.to_integer(sec)
        )

      _ ->
        date_str
    end
  end

  @months %{
    "Jan" => 1, "Feb" => 2, "Mar" => 3, "Apr" => 4,
    "May" => 5, "Jun" => 6, "Jul" => 7, "Aug" => 8,
    "Sep" => 9, "Oct" => 10, "Nov" => 11, "Dec" => 12
  }

  defp month_to_number(month), do: Map.fetch!(@months, month)
end
