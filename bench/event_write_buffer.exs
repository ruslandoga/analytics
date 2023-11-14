Benchee.init([])
|> Benchee.system()
|> Map.fetch!(:system)
|> Enum.each(fn {k, v} -> IO.inspect(v, label: k) end)

Plausible.IngestRepo.query!("truncate events_v2")

{:ok, pid} = Plausible.Event.WriteBuffer.start_link(name: :bench_event_write_buffer)

event = %Plausible.ClickhouseEventV2{
  name: "pageview",
  site_id: 3,
  hostname: "dummy.site",
  pathname: "/some-page",
  user_id: 6_744_441_728_453_009_796,
  session_id: 5_760_370_699_094_039_040,
  timestamp: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second),
  country_code: "KR",
  city_geoname_id: 123,
  screen_size: "Desktop",
  operating_system: "Mac",
  operating_system_version: "10.15",
  browser: "Opera",
  browser_version: "71.0"
}

measured = fn name, f ->
  started_at = System.monotonic_time(:millisecond)
  result = f.()
  it_took = System.monotonic_time(:millisecond) - started_at
  IO.puts("finished #{name} in #{it_took}ms")
  result
end

measured.("insert into buffer", fn ->
  1..1_000_000
  |> Task.async_stream(
    fn _ -> Plausible.Event.WriteBuffer.insert(:bench_event_write_buffer, event) end,
    max_concurrency: 10,
    ordered: false
  )
  |> Stream.run()
end)

IO.puts(
  "message queue length #{Process.info(pid, :message_queue_len) |> elem(1)} after insert and before flush"
)

measured.("flushed", fn ->
  Plausible.Event.WriteBuffer.flush(:bench_event_write_buffer)
end)

IO.puts("inserted #{Plausible.ClickhouseRepo.aggregate("events_v2", :count)} events")
