import Config

build_destinations = fn ->
  [{System.get_env("TELEGRAM_CHAT_ID"), nil},
   {System.get_env("TELEGRAM_CHAT_ID_2"), System.get_env("TELEGRAM_THREAD_ID_2")}]
  |> Enum.reject(fn {id, _} -> is_nil(id) or id == "" end)
  |> Enum.map(fn {id, thread} ->
    %{chat_id: id, thread_id: if(thread, do: String.to_integer(thread))}
  end)
end

if config_env() == :prod do
  config :xai_bot,
    nitter_base_url:
      System.get_env("NITTER_BASE_URL") || raise("NITTER_BASE_URL is required"),
    twitter_list_id:
      System.get_env("TWITTER_LIST_ID") || raise("TWITTER_LIST_ID is required"),
    telegram_bot_token:
      System.get_env("TELEGRAM_BOT_TOKEN") || raise("TELEGRAM_BOT_TOKEN is required"),
    telegram_destinations: build_destinations.(),
    telegram_proxy: System.get_env("TELEGRAM_PROXY"),
    openrouter_api_key: System.get_env("OPENROUTER_API_KEY"),
    telegraph_token: System.get_env("TELEGRAPH_TOKEN")
end

if config_env() == :dev do
  config :xai_bot,
    nitter_base_url: System.get_env("NITTER_BASE_URL", ""),
    twitter_list_id: System.get_env("TWITTER_LIST_ID", ""),
    telegram_bot_token: System.get_env("TELEGRAM_BOT_TOKEN", ""),
    telegram_destinations: build_destinations.(),
    telegram_proxy: System.get_env("TELEGRAM_PROXY"),
    openrouter_api_key: System.get_env("OPENROUTER_API_KEY"),
    telegraph_token: System.get_env("TELEGRAPH_TOKEN")
end
