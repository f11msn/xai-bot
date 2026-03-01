defmodule XaiBot.FeedTest do
  use ExUnit.Case, async: true

  @xml File.read!("test/fixtures/rss_sample.xml")

  describe "parse_rss/1" do
    test "parses items from RSS XML" do
      items = XaiBot.Feed.parse_rss(@xml)
      assert length(items) > 0
    end

    test "each item has required fields" do
      [item | _] = XaiBot.Feed.parse_rss(@xml)

      assert is_binary(item.id)
      assert item.id != ""
      assert is_binary(item.author)
      assert is_binary(item.text)
      assert is_binary(item.link)
      assert is_list(item.urls)
    end

    test "strips HTML from text" do
      items = XaiBot.Feed.parse_rss(@xml)

      Enum.each(items, fn item ->
        refute item.text =~ ~r/<[a-z]+/i
      end)
    end

    test "extracts URLs from description" do
      items = XaiBot.Feed.parse_rss(@xml)
      items_with_urls = Enum.filter(items, fn item -> item.urls != [] end)

      assert length(items_with_urls) > 0

      Enum.each(items_with_urls, fn item ->
        Enum.each(item.urls, fn url ->
          assert String.starts_with?(url, "http")
        end)
      end)
    end

    test "converts nitter links to x.com" do
      items = XaiBot.Feed.parse_rss(@xml)

      Enum.each(items, fn item ->
        assert String.starts_with?(item.link, "https://x.com/")
        refute item.link =~ ~r/#m$/
      end)
    end

    test "strips @ prefix from author" do
      items = XaiBot.Feed.parse_rss(@xml)

      Enum.each(items, fn item ->
        refute String.starts_with?(item.author, "@")
      end)
    end
  end
end
