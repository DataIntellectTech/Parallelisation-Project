# Demo

Two terminals, both in `~/internalWork/Parallelisation-Project`.

- **Terminal 1 is the primary.** Most of the demo runs here, straight at its console, so its own tables (`jobs`, `tasks`, `secondaries`) can be shown as they change. Its log scrolls here too.
- **Terminal 2 is a plain KDB-X process with 8 threads.** It's for the comparison with `peach`, the benchmarks, and loading results the way a user would.

`.primary.newjob` takes three arguments:
- the task type;
- the args, one task each;
- a dict of params for every task (`priority`, `timeout`, `retriesmax`, `memestimate`), or `()!()` for none.

It returns the job id straight away.

**Don't wait in a loop on the primary.** A `while` loop polling `jobs` blocks the primary, so no task updates come in and the job never finishes. Re-run `jobs j` by hand instead.

## 0. Before the demo

```bash
bin/stopall.sh                                # nothing left over from earlier runs
set -a; source config/default.env; set +a
tests/run.sh tests/unit                       # 216 passing
bash tests/integration.sh                     # 15 passing
```
- **Rehearse the night before, then restart the primary.** The task history is kept in memory, so a fresh start makes sections 4 and 5 work as written.
- **Warm the page cache.** Run the `vwap` benchmark lines in section 9 once before the demo. Cold, the first run of anything takes about 9s, nearly all of it reading the HDB from disk. The page cache is shared, so whichever runs first would pay for both.

## 1. Start the framework under its two memory caps

In the default.env file define the env var `HDB_DIR` as 
```
HDB_DIR=/home/jrutledge/internalWork/hdb
```

**Terminal 1:**
```bash
set -a; source config/default.env; set +a
systemd-run --user --scope -p MemoryMax=$CGROUP_MEM_LIMIT -p MemorySwapMax=0 $KDBX_HOME/bin/q src/primary.q -p $PRIMARY_PORT
# systemd-run --user --scope          run the primary in a new cgroup; the secondaries it spawns go in the same one
# -p MemoryMax=$CGROUP_MEM_LIMIT      the kernel's cap, 5GB: above it, the kernel kills a process in the cgroup
# -p MemorySwapMax=0                  kill rather than swap
# $KDBX_HOME/bin/q                    the full path: systemd-run can't see the x alias
```
```q
system "cat ",.primary.cgroupdir,"/memory.max"     / 5368709120: the kernel's cap, 5GB
.primary.memcap                                    / 4294967296: the framework's cap, 4GB
.primary.showstatus[]                              / 8 secondaries, all free
```

**Point out:**
- **Two caps.** Above 4GB the framework stops sending new tasks. Above 5GB the kernel kills one.
- **The gap gives running tasks room to grow** after dispatch has stopped.
- **The kernel always picks a secondary.** Every secondary sets its `oom_score_adj` to 1000, so the kernel never picks the primary.

## 2. Run a job

**Terminal 1:**
```q
days:asc d where not null d:"D"$string key hsym`$getenv`HDB_DIR
count days                                         / 50
j:.primary.newjob[`vwap; days; ()!()]              / one task per day; returns straight away
jobs j                                             / state `done after about a second
select taskid, state, secondaryid, args:first each args from tasks where jobid=j
exec finishedtime-submittedtime from jobs where jobid=j
```

**Point out:**
- **One call submits 50 tasks.** The primary hands them out one per secondary, 8 at a time, and sends the next as each finishes.
- **Only approved task types run.** The type is checked on the primary, and again on the secondary, so a user can't run arbitrary code.
- **The primary only holds paths.** Each secondary saves its result to disk.

## 3. A quick comparison with plain `peach`

**Terminal 2:**
```bash
set -a; source config/default.env; set +a
x -s 8
```
```q
system "l src/approvedtasks.q"                     / the same task functions; load before the HDB, as \l moves into its folder
system "l ",getenv`HDB_DIR
days:date
start:.z.P; r2:raze .task.vwap peach days; .z.P-start                  / one process, 8 threads
h:hopen "J"$getenv`PRIMARY_PORT
r:raze get each h(`.primary.jobpaths; 1)                               / the job from section 2 (job 1 on a fresh start)
r~r2                                                                   / 1b: the same result
```

**Point out:**
- **On 50 days, threads are a little faster.** The framework's extra time goes on:
  - the `.Q.gc[]` after every task;
  - reading memory from `/proc`;
  - IPC;
  - writing each result to disk.
- **What that time buys:**

| | `peach`, 8 threads | Framework, 8 secondaries |
|---|---|---|
| A task uses too much memory | `'-w abort` or the OOM killer takes the whole process: every thread's work is lost | the kernel kills one secondary; its task is labelled `oom`, retried once on its own, the rest carry on; the secondary is restarted |
| Too much at once | nothing stops it | each type's peak is learnt; dispatch sends only what fits under the cap |
| A task hangs | it blocks its thread; nothing can stop it | killed at its timeout, reported, secondary restarted |
| Memory | one heap for everything, rarely gc'd | `.Q.gc[]` after every task; memory before, peak and after recorded per task |
| A failure | one error fails the whole `peach` | retries for the reasons in `RETRY_REASONS`; a failed job cancels its queued parts |
| Results | in memory | on disk; still there after the primary stops |

The full timings are in section 9.

## 4. Memory for each task: before, peak, after the gc

**Terminal 1:**
```q
jm:.primary.newjob[`hold; ([] mb:8#300; secs:8#5); ()!()]      / 8 tasks that each hold 300MB for 5s
.primary.showstatus[]                                          / straight away: 8 busy
select taskid, before:`long$membefore%1048576, peak:`long$memafter%1048576, aftergc:`long$memaftergc%1048576 from tasks where jobid=jm
```
Run the last line after the job is complete. Each task goes from about 2MB, to a 300MB peak, and back to about 2MB after `.Q.gc[]`.

**Point out:**
- **Memory is read from the kernel (`/proc`), not from `.Q.w[]`.** It's what the cgroup enforces, and it can be read while a secondary is busy.
- **The primary now knows that `hold` peaks at about 300MB.** That's used in the next section.
- **RssAnon** is the heap things like tables/results/variables and this is what `.Q.gc[]` gives back
- **RssFile** is mem mapped file like hdb cols, which are loaded on start up to the secondaries
- the primary reads the memory stats of the secondaries with `.primary.pollmem` this is run every second. `.mem.read` is used for reading this data from the OS and is also used at key points in a secondaries task, before, after running a task and after the task is completed and `.Q.gc` is ran

## 5. Memory-aware dispatch

**Terminal 1:** lower the framework's cap to 1GB for this part only. The primary reads it on every dispatch, so it can be changed live.
```q
.primary.memcap:1073741824
jv:.primary.newjob[`hold; ([] mb:8#300; secs:8#3); ()!()]
select taskid, estmb:`long$memestimate%1048576, state from tasks where jobid=jv    / 3 running, 5 queued
```
Wait about 10s for it to finish, then:
```q
select n:count i by dispatchedtime.second from tasks where jobid=jv               / sent 3, 3, 2
.primary.memcap:4294967296                                                        / back to 4GB
```

**Point out:**
- **Each task was given the type's learnt peak as its estimate** (`memestimate`, about 300MB).
- **Dispatch counts what's already committed:** the primary, plus each secondary's memory or its running task's estimate, whichever is bigger. It sends only what fits under the cap, so here that's 3 of the 8 at a time.
- **Before this, all 8 would have gone at once:** 2.4GB against a 1GB cap. Dispatch would only have paused after the fact.
- **A type with no history yet** goes whenever there's any room left.

## 6. Priority: an urgent job goes ahead of a queue

**Terminal 1:**
```q
jl:.primary.newjob[`sleep; 40#3; ()!()]                         / a long job: 40 tasks of 3s, priority 0
ju:.primary.newjob[`sumtil; 1000 2000 3000; ([priority:10])]    / an urgent job, submitted after it
select jobid, priority, state from jobs where jobid in (jl,ju)
select taskid, priority, dispatchedtime from tasks where jobid=ju   / sent as soon as the first secondaries free up
```
Let `jl` finish (about 15s) before the next section.

**Point out:**
- **Every task of a job carries the job's priority.** Dispatch sends the highest priority first, then the oldest.
- **No pre-emption:** a running task is never interrupted.
- **No ageing yet,** so a steady stream of urgent work could starve priority 0.

## 7. Jobs that fail

### 7.1 A timeout

```q
jt:.primary.newjob[`sleep; enlist 20; ([timeout:00:00:05.000])]   / runs for 20s; this job's timeout is 5s
jobs jt                                                             / after about 5s: `failed
select taskid, state, reason, retrycount from tasks where jobid=jt  / `timeout, not retried
```
**What to look for:** the log shows "has run past its timeout … killing pid", then "restarting secondary". `.primary.showstatus[]` shows that secondary with a new pid and `restarts` 1.

**Point out:**
- **A busy secondary can't be interrupted,** so the primary kills its process.
- **A timeout isn't retried,** as it would only time out again.

### 7.2 Out of memory

Part 4 of this job asks for 6000MB, more than the 5GB the kernel allows:
```q
jo:.primary.newjob[`hold; ([] mb:(3#100),6000,8#100; secs:12#5); ()!()]
select taskid, state, reason, retrycount, estmb:`long$memestimate%1048576 from tasks where jobid=jo
```
Re-run the select every few seconds. Part 4 is:
1. killed;
2. back to `queued` with `retrycount` 1 and an estimate of 4096MB;
3. sent again only once everything else has finished;
4. killed again, and left `failed`.
```q
jobs jo                                                    / `failed: "task … failed (oom): …"
system "cat ",.primary.cgroupdir,"/memory.events"          / oom_kill 2
.primary.newjob[`hold; ([] mb:enlist 6000; secs:enlist 5); ()!()]   / refused: killed for memory while running on its own
```
**What to look for in the log:**
1. "killed by the kernel for using too much memory";
2. "retrying task … on its own";
3. the second kill;
4. "leaving it failed";
5. "job … failed";
6. "restarting secondary".

The primary is untouched.

**Point out:**
- **The primary knows it was an OOM** because the cgroup's `oom_kill` count went up.
- **The first kill could be bad luck,** because other tasks were running too. So it's retried once with an estimate of the whole cap, which means it runs on its own.
- **Killed while running alone, it really doesn't fit,** so it isn't retried.
- **The same args are refused before anything runs next time.** So is a whole task type whose tasks need more than the cap.

### 7.3 A secondary that dies

Kill secondary 8 while it's running a task, as if it had crashed:
```q
jk:.primary.newjob[`sleep; 16#3; ()!()]
system "kill -9 ",string first exec pid from secondaries where status=`busy, id=8     / straight away
select taskid, state, reason, retrycount from tasks where jobid=jk, retrycount>0
jobs jk                                                                         / after about 10s: `done
```
**What to look for:** the log shows "marking it as failed (lost)", then "retrying task …", then "restarting secondary".

**Point out:**
- **A `lost` task is retried on another secondary,** up to `TASK_RETRIES_MAX` times, so the job still finishes `done`.
- **A secondary is restarted up to `RESPAWN_MAX` times.**

## 8. Guard rails

```q
.primary.newjob[`rm; enlist "x"; ()!()]                     / refused: not an approved task type
.primary.newjob[`sumtil; 10 20; ([priority:`high])]         / refused: wrong type for priority (should be like 0i)
.primary.newjob[`sumtil; 10 20; ([colour:1])]               / refused: unknown param
```

**Point out:** a job is checked whole before any of it runs, so a bad job never leaves half its tasks queued.

## 9. Benchmarks

Run beforehand, not live: show the results table in the demo.

The same work, three ways:
- **KDB-X, `-s 0`:** one process, one thread.
- **KDB-X, `-s 8`:** one process, 8 threads, `peach`.
- **Framework:** 8 secondaries, 1 thread each.

**Two workloads:**
- **`vwap` over the HDB's 50 days:** one day per task, reading from disk.
- **`sumtil` of 50 × 50,000,000:** pure compute, about 400MB each.

Each time is the average of 3 runs, with the page cache warm. Run each workload once first to warm it.

**Terminal 2** (`x -s 8`, then `x -s 0` or just `x`). Load the task functions and the HDB as in section 3, then run each line 3 times:
```q
n:50#50000000
starttime:.z.P; raze .task.vwap peach date; .z.P-starttime
starttime:.z.P; .task.sumtil peach n; .z.P-starttime
```
With `-s 0`, `peach` runs like `each`.

**Terminal 1:** the primary has no HDB loaded, so get the days from the HDB's folder names. Submit one job at a time, and wait for each to be `done` (`jobs b1` and so on) before submitting the next:
```q
days:asc d where not null d:"D"$string key hsym`$getenv`HDB_DIR
b1:.primary.newjob[`vwap; days; ()!()]
b2:.primary.newjob[`vwap; days; ()!()]
b3:.primary.newjob[`vwap; days; ()!()]
s1:.primary.newjob[`sumtil; 50#50000000; ()!()]
s2:.primary.newjob[`sumtil; 50#50000000; ()!()]
s3:.primary.newjob[`sumtil; 50#50000000; ()!()]
select jobid, tasktype, took:finishedtime-submittedtime from jobs where jobid in (b1,b2,b3,s1,s2,s3)
select avgsecs:avg 1e-9*finishedtime-submittedtime by tasktype from jobs where jobid in (b1,b2,b3,s1,s2,s3)
```

### Results

| | `vwap`, 50 days | `sumtil`, 50 × 50,000,000 |
|---|---|---|
| KDB-X, `-s 0` (one thread) | 3.40s | 4.41s |
| KDB-X, `-s 8` (`peach`) | 0.62s | 0.67s |
| Framework, 8 secondaries, 1 thread each | 1.22s | 2.22s |

**Point out:**
- **The framework is 2–3 times faster than one thread:** 2.8 times for `vwap` and 2.0 times for `sumtil`.
- **On small, even tasks like these, `peach` is faster than the framework:** 2.0 times for `vwap` and 3.3 times for `sumtil`. Every framework task pays a fixed cost:
  - reading memory from `/proc`, and resetting the peak;
  - IPC;
  - writing its result to disk;
  - the `.Q.gc[]` afterwards.
- **The bigger `sumtil` gap is mostly the gc.** Each task gives its 400MB back to the OS, so the next one has to get it again. `peach` threads keep their memory and reuse it.
- **The cost is per task,** so it matters less as tasks get longer.
- **What the extra second buys is the table in section 3:**
  - a memory kill takes out one secondary, not everything;
  - a hung task is killed at its timeout;
  - the global cap is enforced, and dispatch only sends what fits;
  - each task's memory is measured and freed;
  - results are on disk.
- **Homer has 64 logical CPUs:** 32 physical cores across 2 sockets. 8 secondaries or 8 threads use a quarter of the physical cores. It's a shared box, hence the average of 3.
- **Not run: 8 secondaries with 8 threads each.** None of today's task types use threads inside a task, so it would change nothing. It's worth measuring with a task that does, such as a `vwap` over a range of days, which q splits across its threads by itself.

## 10. Getting the results

**Terminal 1:**
```q
.primary.jobpaths j                       / one file per task, in task order: results/<primary start>/<jobid>/<taskid>
.primary.jobpaths jo                      / a failed job: 'job … is failed
select jobid, tasktype, state, resultbytes from jobs
```
**Terminal 2:**
```q
paths:h(`.primary.jobpaths; 1)
r:raze get each paths                     / loaded and combined in the user's session
```
Then stop the primary (`\\` in terminal 1) and load the results again in terminal 2:
```q
r~raze get each paths                     / 1b: the results don't need the primary
```

**Point out:**
- **Results never pass through the primary,** so they can't push its memory over the cap. Each secondary saves its result to disk before its `.Q.gc[]`, and the primary only keeps the path and size.
- **`resultbytes` shows a job's total size,** so a user can see what `raze get each` will load before running it.
- **A task outside a job is saved under `nojob/<taskid>`.**

## 11. Why not `-w`

- **It's per process, not global.** The brief wants one cap across the primary and every secondary. `-w 4GB` on 8 secondaries allows 32GB.
- **It counts the wrong thing.** `-w` limits q's heap. The kernel enforces RSS, which is what the framework measures.
- **It can't be handled.** `'-w abort` exits the process and can't be trapped. With `peach`, every thread's work goes with it.
- **The cgroup does the job better:** one hard cap for the whole group, on real RSS. The kernel also counts each kill, so the task is labelled `oom`.

## 12. What's next

**From the brief, not done yet**
- Backoff between retries.
- Quarantine for a secondary that keeps failing.

**Building on what's there**
- Metrics for each task type: time, peak and failure rate.
- One blocking call, `.primary.run`, that waits for a job and returns its paths.
- Combining a job's results on a secondary, with custom combine functions.
- A retention policy for old results.
- Ageing for priorities, so low-priority work can't be starved.
- Task types that use threads inside a secondary, and benchmark row 4 with them.

**Bigger steps**
- Secondaries on other machines.
- Starting more secondaries when the queue is deep and there's memory to spare.
- Fairness between users.
- Packaging it as a `di.parallel` module.
- Editting message handlers to return result paths to user over IPC or block user until job is completed
- More useful queries to run on secondaries with threads eg. a VWAP with a date range so each secondary could make use of peach

**Benefits IMO**
- big reporting tasks like a hdb which we need to get yearly data for that would kill a normal kdb proc as tasks are split up over different secondaries per date
  - big dbmaint job
  - big reporting
- good for when hardware is limited as we can run multiple processes with a memory cap in their own cgroup, so any bad processes or cgroups will kill themselves instead of blocking other procs