defmodule XaiBot.DigestTest do
  use ExUnit.Case, async: true

  @paper_item %{
    id: "1",
    author: "SciFi",
    text: "New paper: Attention in Constant Time\narxiv.org/abs/2602.13804",
    urls: ["https://arxiv.org/abs/2602.13804"],
    published_at: "Sun, 01 Mar 2026 14:00:00 GMT",
    link: "https://x.com/SciFi/status/1",
    title: "Attention in Constant Time"
  }

  @release_item %{
    id: "2",
    author: "OpenAI",
    text: "Introducing GPT-5: our most capable model yet. Now available in the API.",
    urls: ["https://openai.com/blog/gpt-5"],
    published_at: "Sun, 01 Mar 2026 12:00:00 GMT",
    link: "https://x.com/OpenAI/status/2",
    title: "Introducing GPT-5"
  }

  @tool_item %{
    id: "3",
    author: "huggingface",
    text: "Check out our new library for fast inference. pip install turbo-infer",
    urls: ["https://github.com/huggingface/turbo-infer"],
    published_at: "Sun, 01 Mar 2026 10:00:00 GMT",
    link: "https://x.com/huggingface/status/3",
    title: "turbo-infer"
  }

  @rt_item %{
    id: "4",
    author: "someone",
    text: "Great stuff!",
    urls: [],
    published_at: "Sun, 01 Mar 2026 09:00:00 GMT",
    link: "https://x.com/someone/status/4",
    title: "RT by @someone: Great stuff!"
  }

  @short_item %{
    id: "5",
    author: "bot",
    text: "🔥",
    urls: [],
    published_at: "Sun, 01 Mar 2026 08:00:00 GMT",
    link: "https://x.com/bot/status/5",
    title: "🔥"
  }

  @hiring_item %{
    id: "6",
    author: "corp",
    text: "We're hiring ML engineers! Apply now at careers.example.com",
    urls: ["https://careers.example.com"],
    published_at: "Sun, 01 Mar 2026 07:00:00 GMT",
    link: "https://x.com/corp/status/6",
    title: "We're hiring!"
  }

  describe "build/1" do
    test "categorizes papers" do
      digest = XaiBot.Digest.build([@paper_item])
      assert length(digest[:papers]) == 1
    end

    test "categorizes releases" do
      digest = XaiBot.Digest.build([@release_item])
      assert length(digest[:releases]) == 1
    end

    test "categorizes tools" do
      digest = XaiBot.Digest.build([@tool_item])
      assert length(digest[:tools]) == 1
    end

    test "filters out retweets" do
      digest = XaiBot.Digest.build([@paper_item, @rt_item])
      all_items = Map.values(digest) |> List.flatten()
      refute Enum.any?(all_items, &(&1.id == "4"))
    end

    test "filters out short posts" do
      digest = XaiBot.Digest.build([@paper_item, @short_item])
      all_items = Map.values(digest) |> List.flatten()
      refute Enum.any?(all_items, &(&1.id == "5"))
    end

    test "filters out hiring posts" do
      digest = XaiBot.Digest.build([@paper_item, @hiring_item])
      all_items = Map.values(digest) |> List.flatten()
      refute Enum.any?(all_items, &(&1.id == "6"))
    end

    test "returns all categories even if empty" do
      digest = XaiBot.Digest.build([])
      assert Map.has_key?(digest, :papers)
      assert Map.has_key?(digest, :releases)
      assert Map.has_key?(digest, :tools)
      assert Map.has_key?(digest, :insights)
    end
  end

  describe "format/1" do
    test "returns empty list for empty digest" do
      digest = XaiBot.Digest.build([])
      assert XaiBot.Digest.format(digest) == []
    end

    test "returns separate messages per category" do
      digest = XaiBot.Digest.build([@paper_item, @release_item, @tool_item])
      messages = XaiBot.Digest.format(digest)

      assert is_list(messages)
      assert length(messages) == 3

      combined = Enum.join(messages, "\n")
      assert combined =~ "Papers"
      assert combined =~ "Releases"
      assert combined =~ "Tools"
      assert combined =~ "<b>"
      assert combined =~ "arxiv.org"
    end

    test "includes source links" do
      digest = XaiBot.Digest.build([@paper_item])
      [message] = XaiBot.Digest.format(digest)

      assert message =~ "x.com/SciFi/status/1"
      assert message =~ "@SciFi"
    end
  end
end
