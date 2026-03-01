defmodule XaiBot do
  @moduledoc """
  AI News Telegram Bot.

  Fetches AI news from a Twitter list via Nitter RSS,
  filters and categorizes them, and publishes a digest
  to a Telegram channel.

  ## Quick start in IEx

      XaiBot.run_now()

  """

  defdelegate run_now, to: XaiBot.Scheduler
end
