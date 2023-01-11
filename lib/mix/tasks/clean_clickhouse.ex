defmodule Mix.Tasks.CleanClickhouse do
  use Mix.Task

  def run(_) do
    Mix.Task.run("app.start")
    clean_events = "ALTER TABLE events DELETE WHERE 1"
    clean_sessions = "ALTER TABLE sessions DELETE WHERE 1"
    Plausible.ClickhouseRepo.query!(clean_events)
    Plausible.ClickhouseRepo.query!(clean_sessions)
  end
end
