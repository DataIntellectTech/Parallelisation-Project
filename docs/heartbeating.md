# Heartbeating


Every couple of seconds, each secondary calls `.primary.heartbeatcheck` with its memory as the kernel counts it (RssAnon, from `/proc`). The primary records the time in `lastheartbeat`, and the memory in `rssanon` and `memtime`.

A secondary can't send heartbeats while it's running a task: q is single-threaded, so its timer can't fire until the task ends. So heartbeats show that an idle secondary is alive and how much memory it holds. A busy secondary is watched through its task's timeout, and through the primary's own memory poll, which reads `/proc` directly.

Every second, `.primary.check` marks any `free` secondary with no heartbeat for `STALE_MS` as `stale`, and logs a warning. A stale secondary isn't sent work. Its next heartbeat brings it back to `free`.

A heartbeat never frees a `busy` secondary: one sent just before a task arrived can be processed after dispatch has marked it busy.

| Setting | Meaning |
|---|---|
| `STALE_MS` | how long without a heartbeat before a free secondary is marked stale |