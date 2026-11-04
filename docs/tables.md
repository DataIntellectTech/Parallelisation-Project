# Tables

All tables live in the primary, defined in `schemas/primarytables.q`. Memory figures are in bytes. Times are `.z.P` (local time).

## secondaries

Added, or replaced in full, by `.primary.register` when a secondary connects.

| Column | Type | Meaning | Set by |
|---|---|---|---|
| `id` | long | secondary's id | `.primary.register` |
| `handle` | int | handle opened to primary, null once closed | `.primary.register`; cleared by `.z.pc` |
| `pid` | int | secondary's pid | `.primary.register` |
| `host` | symbol | secondary's host | `.primary.register` |
| `status` | symbol | `free`, `busy`, `stale` or `closed` (see below) | see below |
| `lastheartbeat` | timestamp | the last heartbeat, or registration if none yet | `.primary.register`, `.primary.heartbeatcheck` |
| `consecutivefails` | int | failures in a row; 0 at registration | `.primary.register` |
| `healthy` | boolean | whether the secondary can be given work; 1b at registration | `.primary.register` |
| `spawned` | boolean | if it was started or restarted by this primary | `.primary.register` |
| `starttime` | timestamp | start time | `.primary.register` |
| `registeredtime` | timestamp | when it registered | `.primary.register` |
| `tasktypes` | general list | not used yet; empty | `.primary.register` |
| `currenttask` | long | the task it's running; null when it has none | `.primary.sendtask`; cleared by `.primary.taskupdate`, `.primary.timeout`, `.z.pc` |
| `rssanon` | long | its memory as the kernel counts it (RssAnon), what the global cap adds up | `.primary.pollmem` (always, even mid-task), `.primary.heartbeatcheck` (from `.secondary.heartbeat`, while idle), `.primary.taskupdate` (the task's `memaftergc`) |
| `vmrss` | long | all its resident memory (RssAnon plus file pages) | `.primary.pollmem` |
| `memtime` | timestamp | when `rssanon` was last read | `.primary.pollmem`, `.primary.heartbeatcheck` |

**Status changes**

| From | To | When | By |
|---|---|---|---|
| (none) | `free` | it registers | `.primary.register` |
| `free` | `busy` | it's sent a task | `.primary.sendtask` |
| `busy` | `free` | its task ends (`done` or `failed`) | `.primary.taskupdate` |
| `free` | `stale` | no heartbeat for `STALE_MS` | `.primary.check` |
| `busy` | `stale` | a task couldn't be sent to it | `.primary.sendtask` |
| `stale` | `free` | a heartbeat arrives | `.primary.heartbeatcheck` |
| any | `closed` | its connection closes | `.z.pc` |
| `busy` | `closed` | its task ran past its timeout, so its process is killed | `.primary.timeout` |

A heartbeat never frees a `busy` secondary: one sent just before a task arrived can be processed after dispatch marked it busy.

## tasks

One row per task. Users don't add tasks directly: `.primary.newjob` creates one per arg through `.primary.newtask`.

| Column | Type | Meaning | Set by |
|---|---|---|---|
| `taskid` | long | the task's id; only ever goes up (`.primary.nexttaskid`) | `.primary.newtask` |
| `tasktype` | symbol | the function to run; must be in `TASK_TYPES` on the primary and in `.secondary.approvedtasks` on the secondary | `.primary.newtask` |
| `args` | general list | the task's one argument, stored enlisted (a dict for several inputs) | `.primary.newtask` |
| `priority` | int | higher goes first; ties go oldest first | the job's params in `.primary.newjob` (default 0) |
| `submittedtime` | timestamp | when the task was created | `.primary.newtask` |
| `memestimate` | long | the memory the task is expected to use; dispatch only sends it if it fits under the cap; null always goes | `.primary.newjob`, from `.primary.estimatemem` unless given in the params |
| `timeout` | time | how long the task may run before its secondary is killed | the job's params (default `TASK_TIMEOUT_MS`); checked by `.primary.checktimeouts` |
| `retrycount` | int | retries used | 0 in `.primary.newtask`; +1 in `.primary.retry` |
| `retriesmax` | int | retries allowed | the job's params (default `TASK_RETRIES_MAX`) |
| `state` | symbol | `queued`, `dispatched`, `running`, `done` or `failed` (see below) | only `.primary.taskupdate` |
| `secondaryid` | long | the secondary it was sent to | `.primary.sendtask`; cleared by `.primary.retry` |
| `dispatchedtime` | timestamp | when it was sent | `.primary.taskupdate` (from `.primary.statustime`) |
| `startedtime` | timestamp | when the secondary started it | `.primary.taskupdate`, on `.secondary.runtask`'s `running` message |
| `finishedtime` | timestamp | when it finished or failed | `.primary.taskupdate` |
| `membefore` | long | the secondary's RssAnon just before the task | `.secondary.runtask` (`.mem.readandclear`) |
| `memafter` | long | the peak during the task (VmHWM, reset just before it); for a task killed for memory, the cap it hit | `.secondary.runtask`; `.z.pc` for an OOM |
| `memaftergc` | long | the secondary's RssAnon after its `.Q.gc[]` | `.secondary.runtask` |
| `err` | string | the error, for a failed task | `.secondary.runtask`, `.primary.sendtask`, `.primary.timeout`, `.z.pc`, `.primary.canceljob` |
| `reason` | symbol | why it failed: `error`, `savefailed`, `sendfailed`, `timeout`, `oom`, `lost` or `cancelled`; only reasons in `RETRY_REASONS` are retried | as `err` |
| `resultpath` | symbol | where the result was saved, `RESULTS_DIR/<primary start time>/<taskid>`; null if the task returned `::` | `.secondary.runtask` (`.secondary.save`) |
| `resultbytes` | long | the saved result's size on disk | `.secondary.runtask` (`.secondary.save`) |
| `jobid` | long | the job the task belongs to | `.primary.newjob` |
| `user` | symbol | who submitted it (`.z.u` of the connection that called `.primary.newjob`; the name the client gives, not checked) | `.primary.newjob` |

**State changes** (`.primary.taskchange`)

| From | To | When | By |
|---|---|---|---|
| (none) | `queued` | it's created | `.primary.newtask` |
| `queued` | `dispatched` | it's sent to a secondary | `.primary.sendtask` |
| `queued` | `failed` | its job failed, so it's cancelled | `.primary.canceljob` |
| `dispatched` | `running` | the secondary starts it | `.secondary.runtask` |
| `dispatched` | `failed` | it couldn't be sent, its secondary was lost, or it timed out | `.primary.sendtask`, `.z.pc`, `.primary.timeout` |
| `running` | `done` | it finished and its result was saved | `.secondary.runtask` |
| `running` | `failed` | an error, its result couldn't be saved, it timed out, or its secondary was lost or killed for memory | `.secondary.runtask`, `.primary.timeout`, `.z.pc` |
| `failed` | `queued` | it's retried (its reason is in `RETRY_REASONS` and it has retries left) | `.primary.retry` |

Every change goes through `.primary.taskupdate`, which sets the time column for the new state and, when a task ends, frees its secondary, retries it if it can, checks its job (`.primary.jobcheck`) and dispatches again.

## jobs

One row per job, added by `.primary.newjob`.

| Column | Type | Meaning | Set by |
|---|---|---|---|
| `jobid` | long | the job's id (`.primary.lastjobid`) | `.primary.newjob` |
| `tasktype` | symbol | the task type every task of the job runs | `.primary.newjob` |
| `user` | symbol | who submitted it (`.z.u`) | `.primary.newjob` |
| `ntasks` | int | how many tasks, one per arg | `.primary.newjob` |
| `priority` | int | the priority every task of the job has | `.primary.newjob` |
| `state` | symbol | `running`, `done` or `failed` | `.primary.newjob` (`running`); `.primary.jobcheck` |
| `submittedtime` | timestamp | when it was submitted | `.primary.newjob` |
| `finishedtime` | timestamp | when it finished or failed | `.primary.jobcheck` |
| `resultbytes` | long | the total size of its results on disk, so a user can see what `raze get each .primary.jobpaths jid` will load | `.primary.jobcheck` |
| `err` | string | for a failed job, which task failed, its reason and its error | `.primary.jobcheck` |

**State changes**

| From | To | When | By |
|---|---|---|---|
| (none) | `running` | it's submitted | `.primary.newjob` |
| `running` | `done` | every task is `done` | `.primary.jobcheck` |
| `running` | `failed` | a task fails for good (not retried); its queued tasks are cancelled, running ones finish | `.primary.jobcheck`, then `.primary.canceljob` |

## memhistory

One row per memory poll (`.primary.pollmem`, every second), so memory can be looked at over time. Only the last `MEM_HISTORY_MAX` rows are kept.

<!-- check these column names against schemas/primarytables.q -->

| Column | Type | Meaning |
|---|---|---|
| `time` | timestamp | when the poll ran |
| `total` | long | the primary plus every live secondary (RssAnon): what the global cap is compared with |
| `primary` | long | the primary's own RssAnon |
| `secondaries` | long | every live secondary's RssAnon added up |
| `busy` | int | how many secondaries were busy |
