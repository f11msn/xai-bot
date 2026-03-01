defmodule XaiBot.DedupTest do
  use ExUnit.Case

  setup do
    :dets.delete_all_objects(:xai_bot_seen_ids)
    :ok
  end

  test "new ids are not seen" do
    refute XaiBot.Dedup.seen?("tweet_123")
  end

  test "marked ids are seen" do
    XaiBot.Dedup.mark_seen(["tweet_123", "tweet_456"])
    Process.sleep(10)

    assert XaiBot.Dedup.seen?("tweet_123")
    assert XaiBot.Dedup.seen?("tweet_456")
  end

  test "unmarked ids remain unseen" do
    XaiBot.Dedup.mark_seen(["tweet_123"])
    Process.sleep(10)

    refute XaiBot.Dedup.seen?("tweet_999")
  end

  test "count returns number of seen ids" do
    assert XaiBot.Dedup.count() == 0

    XaiBot.Dedup.mark_seen(["a", "b", "c"])
    Process.sleep(10)

    assert XaiBot.Dedup.count() == 3
  end
end
