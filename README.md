# XaiBot

Telegram-бот для агрегации AI-новостей. Собирает посты из Twitter-списка через Nitter RSS, фильтрует шум, категоризирует и публикует дайджест в Telegram-канал.

## Возможности

- Сбор новостей из Twitter-списка через RSS
- Автоматическая категоризация: Papers, Releases, Tools, Insights
- Фильтрация ретвитов, рекламы, вакансий и коротких постов
- Дедупликация опубликованных записей (DETS, TTL 14 дней)
- Автоматическое решение Anubis anti-bot challenge
- Публикация каждой категории отдельным сообщением
- AI-сводка ключевых событий на русском через DeepSeek V3.2 (OpenRouter)
- Retry с экспоненциальным backoff при ошибках
- Расписание: 2 дайджеста в день (настраивается)

## Архитектура

```
Feed → Digest → Telegram → Summary
 │        │         │          │
 │        │         │          └─ AI-сводка на русском (DeepSeek V3.2)
 │        │         └─ Отправка сообщений через Bot API
 │        └─ Фильтрация, категоризация, форматирование
 └─ RSS-фид + Anubis auto-solve
```

| Модуль | Назначение |
|--------|-----------|
| `Feed` | Загрузка и парсинг RSS, конвертация в структуры |
| `Digest` | Фильтрация шума, категоризация, HTML-форматирование |
| `Summary` | Генерация сводки на русском через DeepSeek V3.2 (OpenRouter) |
| `Telegram` | Отправка сообщений, split по лимиту 4096 байт |
| `Scheduler` | Периодический запуск pipeline, retry |
| `Dedup` | DETS-хранилище опубликованных ID с TTL |
| `Anubis` | Решение proof-of-work challenge, кеширование cookie |
| `HTTP` | Общая обёртка для HTTP-запросов |

## Требования

- Elixir ~> 1.18
- Erlang/OTP 27+
- curl

## Настройка

Создать `.env` в корне проекта:

```bash
export NITTER_BASE_URL="https://your-nitter-instance.com"
export TWITTER_LIST_ID="your_list_id"
export TELEGRAM_BOT_TOKEN="your_bot_token"
export TELEGRAM_CHAT_ID="@your_channel"
export OPENROUTER_API_KEY="your_openrouter_api_key"
# Опционально: дополнительный канал/топик
export TELEGRAM_CHAT_ID_2="-100..."
export TELEGRAM_THREAD_ID_2="51"
```

## Запуск

```bash
mix deps.get
mix run --no-halt
```

Ручной запуск pipeline (из IEx):

```elixir
iex -S mix
XaiBot.run_now()
```

## Тесты

```bash
mix test
```

## Конфигурация

| Параметр | Где | Описание |
|----------|-----|---------|
| `NITTER_BASE_URL` | `.env` | URL Nitter-инстанса |
| `TWITTER_LIST_ID` | `.env` | ID Twitter-списка |
| `TELEGRAM_BOT_TOKEN` | `.env` | Токен Telegram-бота |
| `TELEGRAM_CHAT_ID` | `.env` | ID канала или `@username` |
| `OPENROUTER_API_KEY` | `.env` | API-ключ OpenRouter (опционально) |
| `schedule_hours` | `config.exs` | Часы запуска (UTC), по умолчанию `[6, 18]` |
| `socks5_proxy` | `config.exs` | SOCKS5-прокси для запросов |
