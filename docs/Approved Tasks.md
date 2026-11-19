# Approved tasks

A task type is a q function the secondaries are allowed to run. Only approved task types can run, and
they're checked twice:
- **The primary** refuses any task or job whose type isn't in `TASK_TYPES`.
- **Each secondary** refuses any task type that isn't in its own `.secondary.approvedtasks` dict, even if
  the primary sent it. The task fails with `unknown tasktype: <name>`.

So nothing outside this list can be run on a secondary, whatever a client sends.

## Adding a task type

1. **Write the function in `src/approvedtasks.q`** as `.task.<name>`, then add it to the approved dict:
   ```q
   // what it does, and an example call
   // .task.myavg ([tbl:`trades; d:2014.04.21])
   .task.myavg:{[a] select avg price by sym from a[`tbl] where date=a`d};
   .secondary.approvedtasks[`myavg]:.task.myavg;
   ```
2. **Add its name to `TASK_TYPES`** in `config/default.env` (and in `config/integration.env` if the tests
   use it):
   ```bash
   TASK_TYPES=sumtil,sleep,fail,hold,vwap,myavg
   ```
3. **Restart the primary.** It reads `TASK_TYPES` at start, and the secondaries it spawns load
   `src/approvedtasks.q` when they start.
4. **Try it:**
   ```q
   .primary.newtask ([tasktype:`myavg; args:([tbl:`trades; d:2014.04.21])])
   .primary.newjob[`myavg; ([] tbl:2#`trades; d:2014.04.21 2014.04.22); ()!()]
   ```

### Rules for a task function

- **It takes exactly one argument.** For several inputs, take a dict: `{[a] ... a`mb ... a`secs}`. A job
  given a table passes each row as a dict, so `([] mb:100 200; secs:1 2)` makes two tasks.
- **Its return value is the result.** The secondary saves it to disk with `set` and only the path goes back
  to the primary. So it must be something `set` can write: atoms, lists, dicts and tables are all fine.
  Return `::` for no result: no file is saved.
- **An error fails the task.** Anything it signals (`'oops`) is caught: the task fails with reason `error`,
  and the message goes in `err`. Errors are not retried.
- **It mustn't keep memory in globals.** After each task the secondary runs `.Q.gc[]` to give the memory
  back. That only works for memory nothing still refers to: a task that sets a global keeps that memory
  for the life of the secondary, and every later task's memory figures include it.
- **Long tasks need a long enough `timeout`.** A task running past `TASK_TIMEOUT_MS` (or its own `timeout`)
  fails, and its secondary is killed. Give a slow task type its own `timeout` when you submit it.
- **It can use secondary threads.** Each secondary starts with `-s THREADS` (default 1). With more, a task
  can use `peach` inside itself.
- **An HDB is loaded for it if `HDB_DIR` is set.** Each secondary loads that HDB at start, so a task can
  query its tables directly (see `vwap`).

### Naming

- The function is `.task.<name>`, and the approved key is the same name: `` `myavg ``.
- Names are lowercase, with no underscores.

### Testing a task without the framework

Load the file in a plain q session and call the function:
```bash
x src/approvedtasks.q
```
```q
.task.sumtil 1000                          / 499500
.secondary.approvedtasks[`hold] ([mb:100; secs:1])
\l /path/to/hdb                            / for a task that reads an HDB
.task.vwap 2014.04.21
```

## The approved tasks

| Task type | Argument | Returns | Used for |
|---|---|---|---|
| `sumtil` | a number `n` | `sum til n` | quick CPU work; tests, demos |
| `sleep` | a number of seconds | an empty list | a task that takes a known time; timeouts, priority, busy secondaries |
| `fail` | anything (ignored) | never returns: always fails | the failure path: `failed`, reason `error`, cancelling a job |
| `hold` | a dict `` `mb`secs `` | the number of longs it held | a known amount of memory for a known time; memory gating, gc, OOM |
| `vwap` | a date | a table: `vwap` by `date`, `sym` | a real HDB query, one task per date |

### `sumtil`

```q
.task.sumtil:{sum til x};
```
Adds up `0` to `n-1`. Bigger `n` takes longer and uses more memory: `til n` is a list of `n` longs (8
bytes each), so `n` of 50,000,000 uses about 400MB at its peak.
```q
.primary.newtask ([tasktype:`sumtil; args:1000])            / result 499500
.primary.newjob[`sumtil; 1000 2000 3000; ()!()]             / 499500 1999000 4498500
```

### `sleep`

```q
.task.sleep:{system"sleep ",string x};
```
Waits `x` seconds, using no memory or CPU. Useful for keeping secondaries busy, and for testing timeouts
and priority.
```q
.primary.newtask ([tasktype:`sleep; args:10; timeout:00:00:02.000])   / fails as timeout after ~2s
.primary.newjob[`sleep; 8#5; ()!()]                                   / keeps 8 secondaries busy for 5s
```

### `fail`

```q
.task.fail:{'`fail};
```
Always signals `'fail`. The task fails with reason `error` and `err` "fail", and it isn't retried. In a
job, the first one to fail makes the job fail and cancels its queued tasks.
```q
.primary.newtask ([tasktype:`fail; args:1])
.primary.newjob[`fail; til 20; ()!()]
```

### `hold`

```q
.task.hold:{[a] v:(a[`mb]*131072)#0; system "sleep ",string a`secs; count v};
```
Takes `mb` MB of memory and keeps it for `secs` seconds:
- 131,072 longs is 1MB, and filling them with 0 writes every page, so the memory really is used and the
  kernel counts it (RssAnon).
- It returns the number of longs, not the list, so the saved result is tiny.

It's how the memory features are tested:
- **The global cap:** several 300MB tasks pause dispatch under a low cap.
- **gc:** memory before, at the peak and after `.Q.gc[]`.
- **OOM:** a 2000MB task under a 1GB kernel cap is killed and labelled `oom`.
- **Memory estimates:** the next `hold` job is estimated at the biggest seen.
```q
.primary.newtask ([tasktype:`hold; args:([mb:300; secs:2])])
.primary.newjob[`hold; ([] mb:300 300 300; secs:2 3 4); ()!()]
```

### `vwap`

```q
.task.vwap:{[d]
  select vwap: size wavg price by date,sym from trades where date = d
 };
```
The volume-weighted average price for every symbol on one date, from the HDB's `trades` table. It needs
`HDB_DIR` set to a date-partitioned HDB with a `trades` table (`date`, `sym`, `price`, `size`). One task per
date, then join the results:
```q
j:.primary.newjob[`vwap; 2014.04.21 2014.04.22 2014.04.23; ()!()]
raze get each .primary.jobpaths j        / one table: vwap by date, sym
```