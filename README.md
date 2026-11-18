# Parallelisation-Project
Build a pure q parallelisation framework with a primary process that can spin up secondary processes to complete jobs


## Overview

One **primary** process and N **secondary** processes run on one machine.

- **The primary** owns the task queue. It decides which task runs where and watches memory against one cap for the primary and every secondary together (`GLOBAL_MEM_LIMIT`). It holds back new work while memory is over that cap.
- **The secondaries** run tasks, one at a time. They report back to the primary: status, memory, results. After each task they run `.Q.gc[]`, so its memory is returned before the next one.
- **Jobs:** work is submitted as a job, one task type and a list of args. The primary makes one task per arg and spreads them across the secondaries. Each secondary saves its result to disk and returns only the path, so results never pass through the primary.
- **Global memory cap:** the primary reads its own and every secondary's memory every second, busy secondaries included. While the total is over `GLOBAL_MEM_LIMIT`, no new task is sent; dispatch resumes once memory falls back under. Tasks already running carry on.

## Getting started

**Pre-requisites**
- KDB-X, with `KDBX_HOME` set. The framework uses its `kx.log`, `di.timer` and `di.os` modules.
- Linux. Memory figures are read from `/proc`, and the kernel's memory cap uses cgroups v2.
- For the kernel's memory cap, a systemd user session (`systemd-run --user`). This part is optional: without it, start with `USE_CGROUP=0` and only the framework's cap applies.

**Set up:**
```bash
git clone git@github.com:DataIntellectTech/Parallelisation-Project.git
cd Parallelisation-Project
```
Then edit `config/default.env`. These are the settings to look at first:

| Setting | What it is |
|---|---|
| `PRIMARY_PORT` | the port the primary listens on |
| `NUM_SECONDARYS` | how many secondaries the primary starts |
| `GLOBAL_MEM_LIMIT` | the frameworks memory cap in bytes, for the primary and every secondary together; empty means no cap |
| `CGROUP_MEM_LIMIT` | the kernel's memory cap in bytes, used when starting under a cgroup: above it, the kernel kills a secondary. Must be above `GLOBAL_MEM_LIMIT`, roughly x1.25 |
| `RESULTS_DIR` | where task results are saved |
| `TASK_TYPES` | the task types users may run |
| `HDB_DIR` | an HDB for the secondaries to load, if your tasks need one |

Run every command from the repo's top folder, as the scripts load files by relative path.

## Starting the primary

Load the config into the environment first, in every terminal you use:
```bash
# source env vars
set -a; source config/default.env; set +a

# start with no cap useful for development
x src/primary.q -p $PRIMARY_PORT

# start with cgroups and a memory cap
systemd-run --user --scope -p MemoryMax=$CGROUP_MEM_LIMIT -p MemorySwapMax=0 $KDBX_HOME/bin/q src/primary.q -p $PRIMARY_PORT
```

There are two caps. `GLOBAL_MEM_LIMIT` is the framework's: above it, dispatch pauses. `CGROUP_MEM_LIMIT` is the kernel's: above it, the kernel kills a process in the cgroup (a secondary, never the primary). The kernel's cap must be higher. With swap off, the kernel acts the moment a process tries to go past its cap, so if the two were equal, the framework would never get to pause. The gap gives tasks already running room to keep growing after dispatch has paused. Every secondary sets its `oom_score_adj` to 1000 when it starts, and the primary keeps 0, so when the cgroup runs out of memory the kernel picks a secondary.

Or use the scripts, which load the config themselves and run the primary in the background:
```bash
bin/startprimary.sh                  # under a cgroup capped at CGROUP_MEM_LIMIT
USE_CGROUP=0 bin/startprimary.sh     # without the kernel's cap
bin/startsecondary.sh 9              # start one more secondary by hand
bin/stopall.sh                       # stop the primary and every secondary for this config
```
Each script takes the config file as its last argument (default `config/default.env`). Logs go to `logs/`, and the primary's pid to `logs/primary.pid`. To check the kernel's cap on a running primary:
```bash
cat /sys/fs/cgroup$(cut -d: -f3 /proc/$(cat logs/primary.pid)/cgroup)/memory.max
```


After starting the primary it will spin up secondaries itself, current default amount is 8.

To check that it's up, in the primary:
```q
.primary.showstatus[]      / memory, dispatch, every secondary and the task counts
```

### Stopping primary and secondaries
To stop everything, quit the primary (`\\`): it asks its secondaries to exit, and kills any still running after `STOP_GRACE_PERIOD_SECS`. To start one more secondary from the primary, use `.primary.spawn <next available id>`. From a shell, `bin/stopall.sh` stops everything the same way, and kills anything still running after the grace period.

## Running a job

Work is submitted as **jobs**, from any q session. A job is one task type and a list of args: the primary
makes one task per arg and runs them across the secondaries.
```q
h:hopen 45000

/ one job, three tasks; returns the job id straight away
j:h(`.primary.newjob; `sumtil; 1000 2000 3000; ()!())

/ repeat until state is `done (or `failed: see err)
h({jobs x}; j)

/ the results: one file per task, in task order; load and combine them yourself
paths:h(`.primary.jobpaths; j)
raze get each paths
```
For several inputs per task, pass a table: each row becomes one task's args, as a dict.

**Params,** for every task of the job (`()!()` for none):

| Param | Type | Default | Meaning |
|---|---|---|---|
| `priority` | int | 0 | higher goes first; ties go oldest first |
| `timeout` | time | `TASK_TIMEOUT_MS` | a task running longer than this has its secondary killed |
| `retriesmax` | int | `TASK_RETRIES_MAX` | how many retries, for the reasons in `RETRY_REASONS` |
| `memestimate` | long | learnt | the memory each task is expected to use, in bytes; learnt from earlier tasks of the type if not given |

For example:
```q
h(`.primary.newjob; `vwap; 2014.04.21 2014.04.22; ([priority:10; timeout:00:00:30.000]))
```

**Other calls:**
```q
h({select taskid, state, reason, err from tasks where jobid=x}; j)   / the job's tasks
h(`.primary.canceljob; j)                                           / cancel its queued tasks
h".primary.status[]"                                                / the status as a dict
```

**A job is refused before anything runs** (the call errors and no task is made) if:
- its task type isn't approved, or it has no args;
- a param is unknown, or of the wrong type (`priority` and `retriesmax` accept any whole number);
- earlier tasks of its type needed at least `GLOBAL_MEM_LIMIT`, so it could never fit;
- any of its args were killed for memory before, under a kernel cap (`CGROUP_MEM_LIMIT`) at least as
  high as now. Raising that cap lets them run again.

**A job fails** as soon as one of its tasks fails for good, that is, after any retries. Its queued tasks
are then cancelled and never sent; tasks already running finish. `err` on the job says which task failed
and why.

**Results** are saved under `RESULTS_DIR/<primary start time>/<jobid>/<taskid>`. A task submitted on its
own, outside a job, goes under `RESULTS_DIR/<primary start time>/nojob/<taskid>`.

Each job and its tasks record the user who submitted it (`.z.u`: the name the client gives, not checked).

More detail, including the memory estimate and every error message, is in [Jobs](docs/jobs.md).

**Adding a task type:**
1. Add the function to `src/approvedtasks.q`. It takes exactly one argument; for several inputs, use a dict.
2. Add its name to `TASK_TYPES`.
3. Restart.

## Status

`.primary.status[]` returns a snapshot of the primary as a dict, for code to read:

| Key | What it holds |
|---|---|
| `time`, `uptime` | when the snapshot was taken (UTC) and how long the primary has been running |
| `memory` | `total` in use (the primary plus every live secondary, RssAnon, bytes), `cap` (`GLOBAL_MEM_LIMIT`), `headroom` (cap minus total), `primary` (the primary's own) |
| `dispatch` | `paused`, `pausecount`, `pausedtotal` (includes the current pause), `pausedsince` |
| `secondaries` | one row per secondary: id, pid, status, spawned, current task, rssanon, restarts, time since its last heartbeat (`lastseen`) |
| `seccounts` | how many secondaries are free, busy, stale and closed |
| `taskcounts` | how many tasks are queued, dispatched, running, done and failed |

`.primary.showstatus[]` prints the same snapshot for a person at the console:

    == primary status 2026.11.13D13:51:09.408361778  uptime 0D00:01:29.987809969 ==
    memory: 17MB in use, 4096MB cap, 4079MB headroom
    dispatch: running, paused 0 times for 0D00:00:00.000000000
    secondaries: 8 free, 0 busy, 0 stale, 0 closed
    id pid     status spawned task memmb restarts lastseen
    ----------------------------------------------------------
    1  3775257 free   1            2.1   0        00:00:00.641
    ...
    tasks: 0 queued, 0 dispatched, 0 running, 1 done, 1 failed

A closed secondary keeps its last memory reading in the table but is not counted in the total.

## Failures

- **Errors** in a task's own code are reported (`failed`, reason `error`) and not retried.
- **A secondary that dies mid-task:** its task fails as `lost` and is retried on another
  secondary. The secondary is restarted, up to `RESPAWN_MAX` times.
- **A task that runs too long:** it fails as `timeout` and isn't retried. Its secondary is
  killed, since a busy q process can't be interrupted, and then restarted.
- **A secondary the kernel kills for memory** (over `CGROUP_MEM_LIMIT`): its task fails as `oom`
  and isn't retried, since the same args would need the same memory again. Its `memafter` records
  the kernel's cap. The secondary is restarted, up to `RESPAWN_MAX` times.

Per task, `timeout` and `retriesmax` can be set when it's submitted; otherwise
`TASK_TIMEOUT_MS` and `TASK_RETRIES_MAX` apply:
```q
.primary.newtask ([tasktype:`sleep; args:10; timeout:00:00:02.000; retriesmax:1i])
```
More detail, including the order things happen in, is in [How it works](docs/howitworks.md#failures), and how a memory kill is spotted is in [Memory kills](docs/howitworks.md#memory-kills).

## Memory polling

All memory figures come from the kernel, in `/proc/<pid>/status`, in bytes. The framework doesn't use `.Q.w[]`: the kernel's figures are what it actually enforces, and they can be read from outside a process, which matters because a secondary running a task can't answer.

| Figure | What it counts, in q terms |
|---|---|
| RssAnon | q's heap: vectors, tables, dicts and query results held in memory, plus IPC buffers. What `.Q.gc[]` gives back |
| RssFile | memory-mapped files: HDB column files a query has touched, and anything `get` maps rather than copies. Shared between processes, and the kernel can drop it under pressure |
| VmRSS | the two together |
| VmHWM | the highest VmRSS since the peak was last reset |

**Who reads what, and when**
- **The primary,** every second: its own RssAnon and every live secondary's, in one read, including busy secondaries, since nothing is asked of them. Each secondary's figure is kept in `secondaries`, and the total as a row in `memhistory` (the last `MEM_HISTORY_MAX` rows).
- **Each idle secondary,** every couple of seconds: sends its RssAnon with its heartbeat.
- **Each task,** recorded by its secondary:
  - `membefore`: RssAnon just before the task. The peak is reset (`clear_refs`) at the same moment
  - `memafter`: VmHWM at the end, the task's peak. RssAnon is only a snapshot of one moment, and would miss a spike while the task runs
  - `memaftergc`: RssAnon after the `.Q.gc[]` that follows the task. The primary uses it straight away, so freed memory counts before the next poll.

**The global cap.** While the total (the primary plus every live secondary) is over `GLOBAL_MEM_LIMIT`, dispatch sends nothing new. It resumes when the total falls back under. Each pause and resume is logged, and counted in `.primary.pausecount` and `.primary.pausedtotal`. Tasks already running are never stopped: the cap only holds back new ones. `.primary.pausedtotal` covers finished pauses; one still in progress started at `.primary.pausedsince`. Under a cgroup, the kernel's own cap (`CGROUP_MEM_LIMIT`) sits above this one, so the framework pauses before the kernel has to kill anything.

```q
-5#memhistory                                       / the last 5 readings: total, primary, secondaries, busy
select id, status, rssanon, memtime from secondaries
.primary.pausecount                                 / how many times dispatch has paused
```

**A known overstatement.** A task's `memafter − membefore` includes file pages it read: the peak counts them, but "before" doesn't. For a task that reads an HDB, that's the heap it used **plus** the pages it touched: on a 31-day query, about 145MB more. For tasks that only compute, it's accurate. The kernel keeps no peak for the heap alone, and q's `.Q.w[]`peak` can't be reset for each task, so VmHWM is the only per-task peak available. The error is on the safe side: the cgroup counts file pages too, and an estimate thats too high holds tasks back rather than letting too many run.


## Tests

```bash
tests/run.sh tests/unit          # unit specs (qspec)
bash tests/integration.sh        # end to end: starts a real primary and secondaries, using config/integration.env
```

## AI usage

This project was built with the help of Claude

**What it did:**
- **Code:** Code was written mostly by me checking functions against Claude with the exception of when we needed to get meory stats from the kernal and start with cgroups. Anything in the code that I used Claude for is marked with a `// Claude`.
- **Tests:** most of the specs were AI-written, I made some corrections and fixes. Claude helped install qspec. I started off reviewing teh unit and integreation tests but along the way it seemed it was only style issues so just ran them and reported errors back to Claude for it to fix
- **Docs:** first drafts of these docs