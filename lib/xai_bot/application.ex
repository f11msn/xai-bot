defmodule XaiBot.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: XaiBot.TaskSupervisor},
      XaiBot.Dedup,
      XaiBot.Scheduler
    ]

    opts = [strategy: :one_for_one, name: XaiBot.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
