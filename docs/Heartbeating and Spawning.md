# Heartbeating and Spawning

## Heartbeating
Every couple of seconds, each secondary calls `.primary.heartbeatcheck` with its memory as the kernel counts it (RssAnon, from `/proc`). The primary records the time in `lastheartbeat`, and the memory in `rssanon` and `memtime`.

A secondary can't send heartbeats while it's running a task: q is single-threaded, so its timer can't fire until the task ends. So heartbeats show that an idle secondary is alive and how much memory it holds. A busy secondary is watched through its task's timeout, and through the primary's own memory poll, which reads `/proc` directly.

Every second, `.primary.check` marks any `free` secondary with no heartbeat for `STALE_MS` as `stale`, and logs a warning. A stale secondary isn't sent work. Its next heartbeat brings it back to `free`.

A heartbeat never frees a `busy` secondary: one sent just before a task arrived can be processed after dispatch has marked it busy.

| Setting | Meaning |
|---|---|
| `STALE_MS` | how long without a heartbeat before a free secondary is marked stale |

## Spawning

**With the primary.** With `SPAWN_SECONDARY=1`, `.primary.start` starts `NUM_SECONDARYS` secondaries, ids 1 to N, each with `.primary.spawn`. Each one:
- runs in the background as `$KDBX_HOME/bin/q src/secondary.q -id n -s THREADS`, with no listening port;
- inherits the primary's environment, so it reads the same config;
- logs to `LOG_DIR/sec<n>.<time>.log`;
- connects back and registers like any other secondary.

The primary keeps the pids of the secondaries it started in `.primary.spawned`, and their rows in `secondaries` have `spawned` set to `1b`.

**By hand, from the primary:**
```q
.primary.spawn 5          / start secondary 5
.primary.nextid[]         / the lowest id not in use
```
`.primary.spawn` refuses an id that's already in use (any row not `closed`), and says which id is free.

**By hand, from a shell**, for a secondary the primary didn't start:
```bash
bash bin/startsecondary.sh 5                   # in the background; log in logs/, pid in logs/sec5.pid
x src/secondary.q -id 5 -s 1                   # interactively (load the config into the environment first)
```

### When a secondary goes away

When a secondary's connection closes, because it exited, was killed or crashed, `.z.pc` marks its row `closed` and clears its `handle`. Closing any other connection, such as a user's, changes nothing. A closed id can be started again, and its row is replaced in full when it re-registers.

### Stopping them

`.primary.stop` stops every connected secondary:
1. asks each one to exit, by sending `.secondary.stop` down its connection;
2. waits `STOP_GRACE_PERIOD_SECS`;
3. kills (`kill -9`) any secondary the primary started that's still running.

When the primary quits (`\\`), `.z.exit` calls `.primary.stop` if it started any secondaries. Secondaries started by hand also exit when the primary goes, because their own `.z.pc` sees the connection close.

| Setting | Meaning |
|---|---|
| `SPAWN_SECONDARY` | `1`: the primary starts its secondaries when it starts |
| `NUM_SECONDARYS` | how many it starts |
| `THREADS` | q threads (`-s`) for each secondary; 1 if not set |
| `LOG_DIR` | where secondaries' logs go |
| `STOP_GRACE_PERIOD_SECS` | how long `.primary.stop` waits before killing secondaries that haven't exited |
| `KDBX_HOME` | where KDB-X is installed; secondaries run `$KDBX_HOME/bin/q` |