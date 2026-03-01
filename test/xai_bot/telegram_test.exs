defmodule XaiBot.TelegramTest do
  use ExUnit.Case, async: true

  describe "split_message/1" do
    test "returns single chunk for short messages" do
      text = "Hello world"
      assert XaiBot.Telegram.split_message(text) == [text]
    end

    test "splits long messages at paragraph boundaries" do
      paragraphs = for i <- 1..100, do: "Paragraph #{i} with some content to make it longer."
      text = Enum.join(paragraphs, "\n\n")

      chunks = XaiBot.Telegram.split_message(text)
      assert length(chunks) > 1

      Enum.each(chunks, fn chunk ->
        assert byte_size(chunk) <= 4096
      end)
    end

    test "preserves all content after splitting" do
      paragraphs = for i <- 1..50, do: "Paragraph #{i} text."
      text = Enum.join(paragraphs, "\n\n")
      chunks = XaiBot.Telegram.split_message(text)
      reassembled = Enum.join(chunks, "\n\n")

      assert reassembled == text
    end
  end
end
