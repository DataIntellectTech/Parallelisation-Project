# Jobs and Tasks

Work runs as **tasks**: one whitelisted function call, sent to a secondary. Most work is submitted as a
**job**: one task type and a list of args, which the primary splits into one task per arg and tracks as a
whole.

## Jobs

A job is `done` when every one of its tasks is done, and `failed` as soon as one task fails for good.

### Running a job

From any q session:
```q
h:hopen 45000                                     / the primary's PRIMARY_PORT
j:h(`.primary.newjob; tasktype; args; params)     / returns the job id straight away
```

| Argument | What it is |
|---|---|
| `tasktype` | a symbol, one of `TASK_TYPES`, e.g. `` `vwap `` |
| `args` | one item per task: a list, e.g. `2014.04.21 2014.04.22`, or a table, one row per task (each row reaches the task as a dict) |
| `params` | a dict of optional settings for every task of the job; `()!()` for none |

Examples:
```q
/ three tasks, one per number
h(`.primary.newjob; `sumtil; 1000 2000 3000; ()!())

/ one task per date, high priority, 30 second timeout
h(`.primary.newjob; `vwap; 2014.04.21 2014.04.22 2014.04.23; ([priority:10; timeout:00:00:30.000]))

/ several inputs per task: a table, each row becomes a dict
h(`.primary.newjob; `hold; ([] mb:100 200; secs:1 2); ()!())

/ a single task: still a list of one
h(`.primary.newjob; `hold; enlist ([mb:300; secs:1]); ()!())
```

**Params:**

| Param | Type | Default | Meaning |
|---|---|---|---|
| `priority` | int | 0 | higher goes first; ties go oldest first |
| `timeout` | time | `TASK_TIMEOUT_MS` | a task running longer than this fails as `timeout` and its secondary is killed |
| `retriesmax` | int | `TASK_RETRIES_MAX` | how many times a task is retried, for the reasons in `RETRY_REASONS` |
| `memestimate` | long | learnt | the memory each task is expected to use, in bytes (see Memory estimates) |

Types are checked once, for the whole job:
- `priority` and `retriesmax` accept any whole number: `5` and `5i` both work.
- Every other param must have the type of its default, so `timeout:30000` (a long) is refused; write
  `00:00:30.000`.

The user is not a param: every job and task records `.z.u` of the connection that submitted it (the name
the client gives, not checked).

**What's checked before anything runs.** The call errors, and no task is made, if:

| Problem | Error |
|---|---|
| the task type isn't in `TASK_TYPES` | `'unknown task type nope` |
| no args | `'no args: a job needs at least one task` |
| an unknown param | `'optional params are: priority, memestimate, timeout, retriesmax` |
| a param of the wrong type | `'wrong type for timeout (should be like 00:01:00.000)` |
| earlier tasks of the type needed at least `GLOBAL_MEM_LIMIT` | `'job refused: hold tasks need about 305MB, at or over the cap of 200MB` |
| an arg was killed for memory before, under a kernel cap at least as high as now | `'job refused: 1 of this job's hold args were killed for memory before, under a 1024MB cap (e.g. ...); the kernel's cap is 1024MB` |

A job is all or nothing: if any of its tasks can't be made, the ones already made are deleted.

### Following a job

```q
h({jobs x}; j)                                                                   / the job's row
h({select taskid, state, reason, err, secondaryid from tasks where jobid=x}; j)   / its tasks
```

The `jobs` table has one row per job:

| Column | Meaning |
|---|---|
| `jobid` | the job's id |
| `tasktype` | the task type every task runs |
| `user` | who submitted it |
| `ntasks` | how many tasks, one per arg |
| `priority` | the priority every task has |
| `state` | `running`, `done` or `failed` |
| `submittedtime`, `finishedtime` | when it was submitted, and when it finished or failed (UTC) |
| `resultbytes` | the total size of its results on disk, so you know what loading them will cost |
| `err` | for a failed job: which task failed, its reason and its error |

### How a job ends

Each time one of its tasks ends, `.primary.jobcheck` looks at the job:
- **Every task done:** the job is `done`, and `resultbytes` is the total size of its results.
- **A task failed for good:** the job is `failed`, and `err` names the task, e.g.
  `"task 14 failed (error): fail"`. Its queued tasks are failed as `cancelled`: they're never sent and
  not retried. Tasks already running finish.

A task that's retried doesn't fail its job. `RETRY_REASONS` (default `lost,sendfailed`) covers a secondary
dying or a send failing: the task goes back to `queued` before the job is checked, and the job carries on.

To cancel a job yourself:
```q
h(`.primary.canceljob; j)     / its queued tasks fail as cancelled, running ones finish; the job is failed
```

### Getting a job's results

Each task's result is saved by its secondary, and only the path goes back to the primary. Once the job is
done:
```q
paths:h(`.primary.jobpaths; j)     / the result paths, in task order
raze get each paths                / load and combine them in your own session
```
- `.primary.jobpaths` errors for a job that isn't done, e.g. `'job 4 is failed`.
- A task whose function returns nothing (`::`) saves no file and is left out of the paths.
- `raze` joins lists or tables in task order, whatever order the tasks finished in.

Results are laid out by run, then job:
```
RESULTS_DIR/
  2026.11.18D10.37.20.179692289/      one folder per primary run (its start time)
    1/                                job 1
      1  2  3                         one file per task, named by task id
    2/
      4  5
    nojob/                            tasks submitted on their own, outside a job
      6
```

### Memory estimates

When a job is submitted, `.primary.estimatemem` looks at earlier tasks in the `tasks` table. The table is
held in memory, so this history starts empty each time the primary starts.

**1. The task type.** The estimate is the most any finished task of the type has used: its peak minus its
memory before (`memafter - membefore`).
- If that's at or over `GLOBAL_MEM_LIMIT`, the job is refused: it could never fit.
- A task type that has never run has no estimate. It runs anyway, and its memory is learnt from that run.

**2. The args.** Earlier tasks given any of this job's args are found. Each arg is compared by its
serialised bytes (`-8!`), so dates, numbers, lists and dicts all match.
- If any was killed by the kernel for memory (`oom`) under a kernel cap at least as high as now, the job
  is refused: it would only be killed again. The kernel's cap is `CGROUP_MEM_LIMIT`, or `GLOBAL_MEM_LIMIT`
  if that isn't set.
- Raising `CGROUP_MEM_LIMIT` lets those args run again, estimated at least at the cap they were killed at.
  Raising only `GLOBAL_MEM_LIMIT` doesn't: the kernel would kill them at the same point.

The estimate is stored in each task's `memestimate`, unless the job gave one in its params. It errs high,
never low: it's the biggest seen, and for tasks that read an HDB the peak includes the file pages read.

**For now the estimate only refuses jobs.** Dispatch doesn't use it yet: sending only tasks whose estimates
fit under the cap comes with the V2 scheduler.

## Tasks

A task is a whitelisted function that is sent to a secondary process. A job makes its tasks for you, but you
can also send a single task with the `.primary.newtask` function:
```q
.primary.newtask ([tasktype:`sumtil; args:1000])
```
It returns the task id, or a null (with a warning in the log) if the task is refused: an unknown task type,
a missing `tasktype` or `args`, or an unknown field.

We can also add in extra optional fields:

| Field | Type | Default | Meaning |
|---|---|---|---|
| `priority` | int | 0 | higher is sent first |
| `timeout` | time | `TASK_TIMEOUT_MS` | how long the task may run |
| `retriesmax` | int | `TASK_RETRIES_MAX` | how many times it may be retried |
| `memestimate` | long | null | the memory it's expected to use |

`newtask` doesn't check the fields' types (`newjob` does, once per job), so give them as shown:
`priority:10i`, not `priority:10`.

When all secondaries are busy, tasks are marked as queued and are sent on a first come, first served basis,
unless a task has a higher priority than the others in the queue.

### Running tasks
1. A normal task
```q
.primary.newtask ([tasktype:`sumtil; args:1000])
```

2. Run multiple tasks at once
```q
.primary.newtask each {([tasktype:`sleep; args:x])} each 10#2
```

3. Run a task as high priority
```q
// we have 4 secondaries so lets make everything busy
.primary.newtask each {([tasktype:`sleep; args:x])} each 4#5

// send a low and high priority task
low:.primary.newtask ([tasktype:`sleep; args:1]); high:.primary.newtask ([tasktype:`sleep; args:1; priority:10i])

// we can see the high task was dispatched first
select taskid, priority, dispatchedtime from tasks where taskid in (low,high)
taskid priority dispatchedtime
---------------------------------------------
16     0        2026.11.05D11:52:33.540859541
17     10       2026.11.05D11:52:33.539729147
```

### Task results
A task's result is saved at `RESULTS_DIR/<primary start time>/<jobid>/<taskid>`, or
`RESULTS_DIR/<primary start time>/nojob/<taskid>` for a task sent on its own, before its `.Q.gc[]`. Only the
path and size go back to the primary, in `resultpath` and `resultbytes`, so results never pass through the
primary's memory.

You can get a task's result using the below:
```q
get tasks[1]`resultpath  // 1 is the taskid
```

## Functions

| Function | What it does |
|---|---|
| `.primary.newjob[tasktype; args; params]` | checks the job, makes one task per arg, returns the job id |
| `.primary.jobpaths jid` | a done job's result paths, in task order |
| `.primary.canceljob jid` | fails a job's queued tasks as `cancelled` |
| `.primary.newtask task` | makes a single task outside a job, returns its id |
| `.primary.jobcheck tid` | called by `.primary.taskupdate` when a task ends; sets the job's state |
| `.primary.estimatemem[tasktype; args]` | what earlier tasks say about a job's memory; called by `newjob` |

## Limitations

- **History is in memory only.** The estimates, and the refusals for args killed before, start again from
  nothing each time the primary starts.
- **The user isn't checked.** `.z.u` is whatever name the client gives when it connects.
- **The estimate doesn't steer dispatch yet.** It refuses jobs that can't fit; sending only what fits comes
  with the V2 scheduler.