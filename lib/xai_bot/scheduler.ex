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
    Logger.info("Scheduler started, checking every minute")
    schedule_check()
    {:ok, %{task_ref: nil, last_run_hour: nil}}
  end

  @impl true
  def handle_info(:check, state) do
    state =
      if time_to_run?() and DateTime.utc_now().hour != state.last_run_hour do
        Logger.info("Tick! Running news pipeline")
        state = run_pipeline(state)
        %{state | last_run_hour: DateTime.utc_now().hour}
      else
        state
      end

    schedule_check()
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
      send_all(messages)
      send_summary(digest)
      ids = Enum.map(new_items, & &1.id)
      XaiBot.Dedup.mark_seen(ids)
      Logger.info("Published digest with #{length(new_items)} items in #{length(messages)} messages")
      :ok
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
        [first | rest] = String.split(text, "\n", parts: 2)
        summary_msg = "<b>#{first}</b>\n#{Enum.join(rest)}"

        XaiBot.Telegram.send_message(summary_msg)
        Logger.info("Summary sent")

      {:error, reason} ->
        Logger.warning("Summary generation skipped: #{inspect(reason)}")
    end
  end

  defp send_all(messages) do
    Enum.each(messages, &XaiBot.Telegram.send_message/1)
    :ok
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

  @check_interval :timer.seconds(60)

  defp schedule_check do
    Process.send_after(self(), :check, @check_interval)
  end

  defp time_to_run? do
    hours = Application.get_env(:xai_bot, :schedule_hours, [6, 18])
    now = DateTime.utc_now()
    now.hour in hours and now.minute < 2
  end
end
