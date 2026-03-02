import Config

config :xai_bot,
  schedule_hours: [6, 18],
  socks5_proxy: "localhost:1080",
  data_dir: Path.expand("data", __DIR__ |> Path.dirname())

