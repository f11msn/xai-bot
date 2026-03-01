import Config

if config_env() == :prod do
  config :xai_bot,
    nitter_base_url:
      System.get_env("NITTER_BASE_URL") ||
        raise("NITTER_BASE_URL env var is required"),
    twitter_list_id:
      System.get_env("TWITTER_LIST_ID") ||
        raise("TWITTER_LIST_ID env var is required"),
    telegram_bot_token:
      System.get_env("TELEGRAM_BOT_TOKEN") ||
        raise("TELEGRAM_BOT_TOKEN env var is required"),
    telegram_chat_id:
      System.get_env("TELEGRAM_CHAT_ID") ||
        raise("TELEGRAM_CHAT_ID env var is required"),
    yc_llm_api_key: System.get_env("YC_LLM_API_KEY"),
    yc_folder_id: System.get_env("YC_FOLDER_ID")
end

if config_env() == :dev do
  config :xai_bot,
    nitter_base_url: System.get_env("NITTER_BASE_URL", ""),
    twitter_list_id: System.get_env("TWITTER_LIST_ID", ""),
    telegram_bot_token: System.get_env("TELEGRAM_BOT_TOKEN", ""),
    telegram_chat_id: System.get_env("TELEGRAM_CHAT_ID", ""),
    yc_llm_api_key: System.get_env("YC_LLM_API_KEY"),
    yc_folder_id: System.get_env("YC_FOLDER_ID")
end
