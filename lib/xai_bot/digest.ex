defmodule XaiBot.Digest do
  @moduledoc """
  Filters, categorizes, and formats tweets into a news digest.
  Categories: Papers, Releases, Tools, Insights.
  """

  @retweet_prefix "RT by @"

  def build(items) when is_list(items) do
    items
    |> filter_noise()
    |> Enum.map(&categorize/1)
    |> Enum.group_by(fn {category, _item} -> category end, fn {_category, item} -> item end)
    |> Map.put_new(:papers, [])
    |> Map.put_new(:releases, [])
    |> Map.put_new(:tools, [])
    |> Map.put_new(:insights, [])
  end

  def format(digest) when is_map(digest) do
    [
      format_section("📄 Papers", :papers, digest[:papers]),
      format_section("🚀 Releases", :releases, digest[:releases]),
      format_section("🛠 Tools", :tools, digest[:tools]),
      format_section("💡 Insights", :insights, digest[:insights])
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp filter_noise(items) do
    Enum.reject(items, fn item ->
      retweet?(item) or
        too_short?(item) or
        marketing?(item) or
        hiring?(item)
    end)
  end

  defp retweet?(%{title: title}), do: String.starts_with?(title, @retweet_prefix)
  defp too_short?(%{text: text}), do: String.length(text) < 30
  defp marketing?(%{text: text}), do: text =~ ~r/join us|sign up|discount|promo code/i
  defp hiring?(%{text: text}), do: text =~ ~r/we're hiring|job opening|apply now|careers/i

  defp categorize(item) do
    cond do
      paper?(item) -> {:papers, item}
      release?(item) -> {:releases, item}
      tool?(item) -> {:tools, item}
      true -> {:insights, item}
    end
  end

  defp paper?(item) do
    has_arxiv = Enum.any?(item.urls, &String.contains?(&1, "arxiv.org"))
    text_match = item.text =~ ~r/arxiv|paper|abstract|preprint|cs\.\w{2}/i
    has_arxiv or text_match
  end

  defp release?(item) do
    item.text =~ ~r/released?|launch|announc|v\d+\.\d+|introducing|now available|open.?sourc/i
  end

  defp tool?(item) do
    has_github = Enum.any?(item.urls, &String.contains?(&1, "github.com"))
    text_match = item.text =~ ~r/library|framework|toolkit|CLI|SDK|pip install|npm|cargo/i
    has_github or text_match
  end

  defp format_section(_header, _category, []), do: nil

  defp format_section(header, category, items) do
    entries =
      items
      |> Enum.take(10)
      |> Enum.map(&format_item(&1, category))
      |> Enum.join("\n\n")

    "<b>#{header}</b>\n#{entries}"
  end

  defp format_item(item, :papers) do
    first_line = item.text |> String.split("\n") |> hd()

    links =
      item.urls
      |> Enum.take(2)
      |> Enum.map(fn url -> "🔗 #{url}" end)
      |> Enum.join("\n")

    source = "📌 <a href=\"#{item.link}\">source</a> (@#{item.author})"

    [first_line, links, source]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp format_item(item, _category) do
    first_line = item.text |> String.split("\n") |> hd()
    source = "📌 <a href=\"#{item.link}\">source</a> (@#{item.author})"

    "#{first_line}\n#{source}"
  end
end
