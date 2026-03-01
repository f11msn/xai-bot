defmodule XaiBot.Dedup do
  @moduledoc """
  Deduplication of published tweet IDs.
  DETS-backed with automatic TTL cleanup (14 days).
  """

  use GenServer

  @table :xai_bot_seen_ids
  @ttl_days 14
  @cleanup_interval_ms 6 * 60 * 60 * 1000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def seen?(id) do
    case :dets.lookup(@table, id) do
      [{^id, _ts}] -> true
      _ -> false
    end
  end

  def mark_seen(ids) when is_list(ids) do
    GenServer.cast(__MODULE__, {:mark_seen, ids})
  end

  def count do
    :dets.info(@table, :size)
  end

  @impl true
  def init(opts) do
    path = opts[:path] || data_path()
    File.mkdir_p!(Path.dirname(path))

    {:ok, table} =
      :dets.open_file(@table, type: :set, file: String.to_charlist(path))

    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_cast({:mark_seen, ids}, state) do
    now = System.system_time(:second)
    Enum.each(ids, fn id -> :dets.insert(@table, {id, now}) end)
    :dets.sync(@table)
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    expired = expired_keys()

    if expired != [] do
      Enum.each(expired, fn key -> :dets.delete(@table, key) end)
      :dets.sync(@table)
      require Logger
      Logger.info("Dedup cleanup: removed #{length(expired)} expired entries")
    end

    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :dets.close(@table)
  end

  defp expired_keys do
    cutoff = System.system_time(:second) - @ttl_days * 86_400

    :dets.foldl(
      fn
        {key, ts}, acc when is_integer(ts) and ts < cutoff -> [key | acc]
        {_key, true}, acc -> [acc]
        _, acc -> acc
      end,
      [],
      @table
    )
    |> List.flatten()
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp data_path do
    Path.join(Application.get_env(:xai_bot, :data_dir), "seen_ids.dets")
  end
end
