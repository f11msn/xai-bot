defmodule XaiBot.Scheduler do
  @moduledoc """
  Periodic scheduler for the news pipeline.
  Runs at configured hours (UTC), retries on failure.
  """

  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def run_now do
    GenServer.cast(__MODULE__, :run_now)
  end

  @impl true
  def init(_opts) do
    Logger.info("Scheduler started, scheduling first tick")
    schedule_tick()
    {:ok, %{task_ref: nil}}
  end

  @impl true
  def handle_info(:tick, state) do
    Logger.info("Tick! Running news pipeline")
    state = run_pipeline(state)
    schedule_tick()
    {:noreply, state}
  end

  # Task completed successfully
  def handle_info({ref, result}, %{task_ref: ref} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    case result do
      :ok -> Logger.info("Pipeline completed successfully")
      {:error, reason} -> Logger.error("Pipeline failed: #{inspect(reason)}")
    end

    {:noreply, %{state | task_ref: nil}}
  end

  # Task crashed
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
    Logger.error("Pipeline task crashed: #{inspect(reason)}")
    {:noreply, %{state | task_ref: nil}}
  end

  def handle_info(msg, state) do
    Logger.warning("Scheduler received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_cast(:run_now, state) do
    Logger.info("Manual trigger: running pipeline now")
    state = run_pipeline(state)
    {:noreply, state}
  end

  defp run_pipeline(%{task_ref: nil} = state) do
    task =
      Task.Supervisor.async_nolink(XaiBot.TaskSupervisor, fn ->
        execute_pipeline()
      end)

    %{state | task_ref: task.ref}
  end

  defp run_pipeline(state) do
    Logger.warning("Pipeline already running, skipping")
    state
  end

  @max_retries 3
  @retry_delays [30_000, 60_000, 120_000]

  defp execute_pipeline, do: execute_pipeline(0)

  defp execute_pipeline(attempt) do
    case do_pipeline() do
      :ok ->
        :ok

      {:error, reason} when attempt < @max_retries ->
        delay = Enum.at(@retry_delays, attempt)
        Logger.warning("Pipeline failed (attempt #{attempt + 1}/#{@max_retries + 1}): #{inspect(reason)}, retrying in #{div(delay, 1000)}s")
        Process.sleep(delay)
        execute_pipeline(attempt + 1)

      {:error, _} = err ->
        err
    end
  end

  defp do_pipeline do
    with {:ok, items} <- XaiBot.Feed.fetch(),
         recent_items = filter_recent(items),
         new_items = reject_seen(recent_items),
         digest = XaiBot.Digest.build(new_items),
         messages when messages != [] <- XaiBot.Digest.format(digest),
         messages do
      case send_all(messages) do
        :ok ->
          send_summary(digest)
          ids = Enum.map(new_items, & &1.id)
          XaiBot.Dedup.mark_seen(ids)
          Logger.info("Published digest with #{length(new_items)} items in #{length(messages)} messages")
          :ok

        {:error, _} = err ->
          err
      end
    else
      [] ->
        Logger.info("No new items to publish")
        :ok

      {:error, _} = err ->
        err
    end
  end

  defp send_summary(digest) do
    case XaiBot.Summary.generate(digest) do
      {:ok, text} ->
        summary_msg = "🧠 <b>Сводка</b>\n\n#{text}"

        case XaiBot.Telegram.send_message(summary_msg) do
          :ok -> Logger.info("Summary sent")
          {:error, reason} -> Logger.warning("Failed to send summary: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.warning("Summary generation skipped: #{inspect(reason)}")
    end
  end

  defp send_all(messages) do
    Enum.reduce_while(messages, :ok, fn msg, _acc ->
      case XaiBot.Telegram.send_message(msg) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp filter_recent(items) do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -12 * 3600)

    Enum.filter(items, fn item ->
      case item.published_at do
        %NaiveDateTime{} = dt -> NaiveDateTime.compare(dt, cutoff) != :lt
        _ -> true
      end
    end)
  end

  defp reject_seen(items) do
    Enum.reject(items, fn item -> XaiBot.Dedup.seen?(item.id) end)
  end

  defp schedule_tick do
    delay = ms_until_next_tick()
    Process.send_after(self(), :tick, delay)
    Logger.info("Next tick in #{div(delay, 60_000)} minutes")
  end

  defp ms_until_next_tick do
    hours = Application.get_env(:xai_bot, :schedule_hours, [9, 21])
    now = DateTime.utc_now()
    current_seconds = now.hour * 3600 + now.minute * 60 + now.second

    target_seconds =
      hours
      |> Enum.map(&(&1 * 3600))
      |> Enum.sort()

    next =
      Enum.find(target_seconds, fn t -> t > current_seconds end) ||
        hd(target_seconds) + 86_400

    diff_seconds = next - current_seconds
    diff_seconds = if diff_seconds <= 0, do: diff_seconds + 86_400, else: diff_seconds

    diff_seconds * 1000
  end
end
