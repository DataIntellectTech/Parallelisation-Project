# Parallelisation-Project
Build a pure q parallelisation framework with a primary process that can spin up secondary processes to complete jobs


## Overview

One **primary** process and N **secondary** processes run on one machine.

- **The primary** owns the task queue. It decides which task runs where and watches memory against a single cap for the primary and every secondary together. It holds back new work when that cap would be exceeded.
- **The secondaries** run tasks, one at a time. They report back to the primary: status, memory, results. After each task they run `.Q.gc[]`, so its memory is returned before the next one.


## Getting started

**Pre-requisites**
- KDB-X, with `KDBX_HOME` set. The framework uses its `kx.log`, `di.timer` and `di.os` modules.

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
| `GLOBAL_MEM_LIMIT` | the memory cap in bytes, for the primary and every secondary together; empty means no cap |
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
systemd-run --user --scope -p MemoryMax=$GLOBAL_MEM_LIMIT -p MemorySwapMax=0 $KDBX_HOME/bin/q src/primary.q -p $PRIMARY_PORT
```

After starting the primary it will spin up secondaries itself, current default amount is 8.

To check that it's up, in the primary:
```q
.primary.showstatus[]      / memory, dispatch, every secondary and the task counts
```

### Stopping primary and secondaries
To stop everything, quit the primary (`\\`): it asks its secondaries to exit, and kills any still running after `STOP_GRACE_PERIOD_SECS`. To start one more secondary from the primary, use `.primary.spawn <next available id>`.

## Running a task

Tasks are submitted as **jobs**, from any q session.
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

**Params,** for every task of the job:

| Param | Default | Meaning |
|---|---|---|
| `priority` | 0 | higher goes first; ties go oldest first |
| `timeout` | `TASK_TIMEOUT_MS` | a task running longer than this has its secondary killed |
| `retriesmax` | `TASK_RETRIES_MAX` | how many retries, for the reasons in `RETRY_REASONS` |
| `memestimate` | learnt | the memory each task is expected to use, in bytes |

For example:
```q
h(`.primary.newjob; `vwap; 2014.04.21 2014.04.22; ([priority:10; timeout:00:00:30.000]))
```

**Other calls:**
```q
h(`.primary.canceljob; j)                                   / cancel the job's queued tasks
h({select taskid, state, reason, err from tasks where jobid=x}; j)
h".primary.status[]"                                         / the status as a dict
```

A job is refused before anything runs if:
- its task type isn't approved; or
- earlier tasks of the type needed more memory than the cap; or
- any of its args were killed for memory before, under the same cap or a lower one. Raising the cap lets them run again.

**Adding a task type:**
1. Add the function to `src/approvedtasks.q`. It takes exactly one argument; for several inputs, use a dict.
2. Add its name to `TASK_TYPES`.
3. Restart.

## Memory polling

All memory figures come from the kernel, in `/proc/<pid>/status`, in bytes. The framework doesn't use `.Q.w[]`: the kernel's figures are what it actually enforces, and they can be read from outside a process, which matters because a secondary running a task can't answer.

| Figure | What it counts, in q terms |
|---|---|
| RssAnon | q's heap: vectors, tables, dicts and query results held in memory, plus IPC buffers. What `.Q.gc[]` gives back |
| RssFile | memory-mapped files: HDB column files a query has touched, and anything `get` maps rather than copies. Shared between processes, and the kernel can drop it under pressure |
| VmRSS | the two together |
| VmHWM | the highest VmRSS since the peak was last reset |

**Who reads what, and when**
- **The primary,** every second: its own RssAnon, and every live secondary's, in one read. This includes busy secondaries, since nothing is asked of them. These readings feed the memory cap.
- **Each idle secondary,** every couple of seconds: sends its RssAnon with its heartbeat.
- **Each task,** recorded by its secondary:
  - `membefore`: RssAnon just before the task. The peak is reset (`clear_refs`) at the same moment.
  - `memafter`: VmHWM at the end, the task's peak. RssAnon is only a snapshot of one moment, and would miss a spike while the task runs. VmHWM is the kernel's own record of the highest point.
  - `memaftergc`: RssAnon after the `.Q.gc[]` that follows the task.

**A known overstatement.** A task's memory estimate is `memafter − membefore`. The peak includes file pages the task read, but "before" doesn't. So for a task that reads an HDB, the estimate is the heap it used **plus** the pages it touched: on a 31-day query, about 145MB more. For tasks that only compute, it's accurate. The kernel keeps no peak for the heap alone, and q's `.Q.w[]`peak` can't be reset for each task, so VmHWM is the only per-task peak available. The error is on the safe side: the cgroup counts file pages too, and an estimate that's too high holds tasks back rather than letting too many run.

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