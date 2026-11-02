# Parallelisation-Project
Build a pure q parallelisation framework with a master proc that can spin up secondary procs to complete tasks. 

## Primary 
This is the main process which will manage secondaries and tasks

### how to start
Go to the directory and start this will run the default config and start on port `45000`

```bash
cd /home/jrutledge/internalWork/Parallelisation-Project
bash bin/startprimary.sh
```

For starting it interactively do 
```bash
bash config/config.sh     # this is jsut a coipy of deaful.coinfig and im doing it for testing atm, will probs move out
x src/primary.q -p 45000
```

### tables
**secondaries**

This is a table to monitor the secondary processes used for carrying out tasks assigned by the primary. In this table we track key information such as the `status` of a secondary process.

### Secondaries
These will either be ran as part of the intial start up or the primary will spin up more as needed. They will take the port number `PRIMARY_PORT` + `id` so `secondary 1` would have a port of `45001` and so on. A secondary cannot start if the primary process is not up.

We are going to set all secondaries `oom_score` to `1000`. For anyone not familiar with this `-1000` means shut me down last and `1000` means shut me down first in the case we are out of memory. You can check a processes `oom_score` using `cat /proc/<pid>/oom_score`.

### how to start
To bring up 2 secondaries run the below
```bash
cd /home/jrutledge/internalWork/Parallelisation-Project
bash bin/startsecondary.sh 1
bash bin/startsecondary.sh 2
```

## Testing
We will use the qspec testing framework here, i have copied it into the project directly

### how to run unit tests
From the project top level dir, you run the below commands
```bash
tests/run.sh tests/unit                     # a whole folder
tests/run.sh tests/unit/primarytests.q      # one file
```

Example run
```bash
jrutledge@homer:~/internalWork/Parallelisation-Project$ tests/run.sh tests/unit/primary.q 
.

For 1 specifications, 1 expectations were run.
1 passed, 0 failed.  0 errors.
jrutledge@homer:~/internalWork/Parallelisation-Project$ 
```

### how to run integration tests
From project top level dir run the below commands
```bash
bash tests/integration.sh oomscore   # run just the oomscore_spec.q test
bash tests/integration.sh            # run all integration tests
```
Example output
```bash
jrutledge@homer:~/internalWork/Parallelisation-Project$ bash tests/integration.sh

== tests/integration/stale_spec.q
..

For 1 specifications, 2 expectations were run.
2 passed, 0 failed.  0 errors.
tests/integration.sh: line 25: 2899594 Killed                  "$Q" src/primary.q -p "$PRIMARY_PORT" < /dev/null >> "$LOG_DIR/primary.log" 2>&1

== tests/integration/stop_spec.q
..

For 1 specifications, 2 expectations were run.
2 passed, 0 failed.  0 errors.
tests/integration.sh: line 25: 2899874 Killed                  "$Q" src/primary.q -p "$PRIMARY_PORT" < /dev/null >> "$LOG_DIR/primary.log" 2>&1

integration: all 2 spec files passed
jrutledge@homer:~/internalWork/Parallelisation-Project$ 
```


## Manual testing

A guide to manually test and run commands as i feel it give a bit of confidence to run the code yourself at times. It starts a primary with 4 secondaries and runs tasks through them.

### Start the primary
Go to the directory where you have downloaded hte project to and run the below
```bash
set -a; source config/default.env; set +a
export NUM_SECONDARYS=4
x src/primary.q -p 45000
```

Wait a couple of seconds until all 4 secondaries have registered:

```q
.primary.showstatus[]
```

You should see something like the below
```q
q).primary.showstatus[]
== primary status 2026.10.16D14:39:06.274222113  uptime 0D00:00:06.864868790 ==
secondaries: 4 free, 0 busy, 0 stale, 0 closed
id pid    port  status spawned lastseen     lastmembytes
--------------------------------------------------------
1  527736 45001 free   1       00:00:00.552 620432      
2  527741 45002 free   1       00:00:00.447 620432      
3  527746 45003 free   1       00:00:00.542 620432      
4  527750 45004 free   1       00:00:00.438 620432      
tasks: 0 queued, 0 dispatched, 0 running, 0 done, 0 failed
```

To watch the secondaries work, open a second terminal and follow today's secondary logs. You'll see a `task N is complete` line for each task:

```bash
tail -f logs/sec*.$(date +%Y.%m.%d)*.log
```

### 1. One task, end to end

```q
// run a task and record its taskid
t:.primary.newtask `tasktype`args!(`sumtil;1000000)
// look at the task you just ran
tasks t
// you should see all secondaries as free and tasks having 1 done
.primary.showstatus[]
```

If you increase the size of the argument to the task it will take longer so you can check the tasks and secondaries table to see different status's. This will also increase the `memafter` column as the `heap` will have increased.
eg.

```q
.primary.newtask `tasktype`args!(`sumtil;1000000000)
```

### 2. Many tasks: 20 one-second sleeps on 4 secondaries

```q
ids:.primary.newtask each ([] tasktype:20#`sleep; args:20#1)
```

You can perform the same checks as we did above when just running one task.


### 3. Priority: a high-priority task goes ahead of the queue

First fill all 4 secondaries with 5-second tasks, sleep for 2 seconds then send 4 low and 1 high priority task.

```q
.primary.newtask each ([] tasktype:4#`sleep; args:4#5); system"sleep 2"; lo:.primary.newtask each ([] tasktype:4#`sumtil; args:4#1000); hi:.primary.newtask `tasktype`args`priority!(`sumtil;1000;9i)
```

If we check the tasks table and when each task was dispatched we will see the high priority task was dispatched before the low priority ones.

```q
`dispatchedtime xasc select taskid, tasktype, priority, submittedtime, dispatchedtime from tasks
taskid tasktype priority submittedtime                 dispatchedtime               
------------------------------------------------------------------------------------
9      sumtil   9        2026.10.20D08:51:37.677650727 2026.10.20D08:51:37.678739277
1      sleep    0        2026.10.20D08:51:35.673197691 2026.10.20D08:51:37.679028709
2      sleep    0        2026.10.20D08:51:35.673400356 2026.10.20D08:51:37.679254365
3      sleep    0        2026.10.20D08:51:35.673533294 2026.10.20D08:51:37.679470841
4      sleep    0        2026.10.20D08:51:35.673653260 2026.10.20D08:51:38.696035079
5      sumtil   0        2026.10.20D08:51:37.677263059 2026.10.20D08:51:38.696375433
6      sumtil   0        2026.10.20D08:51:37.677406335 2026.10.20D08:51:38.696626593
7      sumtil   0        2026.10.20D08:51:37.677493443 2026.10.20D08:51:38.696865825
8      sumtil   0        2026.10.20D08:51:37.677572699 2026.10.20D08:51:42.995350280
```

# Benchmarking
trades table is on avg 5100 rows per day
## 1st run
Pri/Sec side:
1. we ran with 4 secondaries
2. `.log.info` was running
3. query was  
```q
alld:d where not null d:"D"$string key hsym `$getenv `HDB_DIR
d:alld where alld within 2014.09.12 2015.09.11
ids:.primary.newtask each ([] tasktype:(count d)#`vwap; args: d)
```
4. this took 1min 9secs (`0D00:01:09.599248039`)
```q
exec count i by state from tasks
raze exec first each result from tasks where state=`done  //result
exec (max finishedtime)-min startedtime from tasks
```
5. only difference is we dont get the result returned
6. dispatch ran every 1 second 

threads side:
1. started `x hdb -s 4`
2. ran much quicker
```q
rutledge@homer:~/internalWork$ x hdb/ -s 8
KDB-X 5.0 2026.07.23 Copyright (C) 1993-2026 Kx Systems
l64/ 64()core 385394MB jrutledge homer.aquaq.co.uk 127.0.1.1 EXPIRE 2027.03.26 dataintellect.com KXMS #104376

.task.vwap:{[d]  select vwap: size wavg price by date,sym from trades where date = d };
alld:d where not null d:"D"$string key hsym `$"/home/jrutledge/internalWork/hdb"
d:alld where alld within 2014.09.12 2015.09.11
startTime:.z.P; .task.vwap peach d ; .z.P-startTime
0D00:00:00.077755113
```

I believe the main difference is the `dispatch` job only running every second, as the first task took ` 0D00:00:00.001581139`

## 2nd run
pri/sec:
1. changed `dispatch` job to check every 0.01 seconds now
2. this has sped it up significantly to 6.5 seconds `0D00:00:06.500832005`

## 3rd run
threads:
1. startged with 8 threads
```q
rutledge@homer:~/internalWork$ x hdb/ -s 8
KDB-X 5.0 2026.07.23 Copyright (C) 1993-2026 Kx Systems
l64/ 64()core 385394MB jrutledge homer.aquaq.co.uk 127.0.1.1 EXPIRE 2027.03.26 dataintellect.com KXMS #104376

.task.vwap:{[d]  select vwap: size wavg price by date,sym from trades where date = d };
alld:d where not null d:"D"$string key hsym `$"/home/jrutledge/internalWork/hdb"
d:alld where alld within 2014.09.12 2015.09.11
startTime:.z.P; .task.vwap peach d ; .z.P-startTime
0D00:00:00.089224031
```

pri/sec:
1. Changed to run 8 secondary processes
2. changed teh `dispatch` to check every 0.0001 seconds
```q
f:{alld:d where not null d:"D"$string key hsym `$getenv `HDB_DIR ; d:alld where alld within 2014.09.12 2015.09.11; ids:.primary.newtask each ([] tasktype:(count d)#`vwap; args: d)}
f[]
exec (max finishedtime)-min startedtime from tasks
0D00:00:03.201173431
```

## 4th run
lets up the amount of data, with fakedb.q we ran
```q
makehdb[`:hdb; 365; 100; 1000000]
```

threads:
```q
.task.vwap:{[d]  select vwap: size wavg price by date,sym from trades where date = d };
alld:d where not null d:"D"$string key hsym `$"/home/jrutledge/internalWork/hdb"
d:alld where alld within 2014.09.12 2015.09.11
startTime:.z.P; .task.vwap peach d ; .z.P-startTime
0D00:00:00.307302246
```

pri/sec:
```q
q)f:{alld:d where not null d:"D"$string key hsym `$getenv `HDB_DIR ; d:alld where alld within 2014.09.12 2015.09.11; ids:.primary.newtask each ([] tasktype:(count d)#`vwap; args: d)}

exec (max finishedtime)-min startedtime from tasks
0D00:00:03.225075485
```

## 5th run
bump up the size of trades again
```
makehdb[`:hdb; 365; 100; 10000000]
// i ctrl+c 'ed this as it was taking ages and homer was tight for disk space
```
will do a smaller date range as i dont want to kill homer

threads (8)
```q
q).task.vwap:{[d]  select vwap: size wavg price by date,sym from trades where date = d };
q)alld:d where not null d:"D"$string key hsym `$"/home/jrutledge/internalWork/hdb"
q)startTime:.z.P; .task.vwap peach alld ; .z.P-startTime
0D00:00:00.643
```

pri/sec:
```q
f:{alld:d where not null d:"D"$string key hsym `$getenv `HDB_DIR ;.primary.newtask each ([] tasktype:(count alld)#`vwap; args: alld)}
f[]

exec (max finishedtime)-min startedtime from tasks
0D00:00:01.348516461
```

## change

after we added the below line to `.primary.taskupdate` so it would rerun after a task is complete instead of waiting for  `.primary.dispatch` to run in our `.timer.getalljobs[]` table.
```
 if[newstate in `done`failed; .primary.dispatch[]];
 ```
 This got the time to 0.939 seconds (`0D00:00:00.939179837`) with the same setup as the 5th run

# AI Usage
1. qspec installation
2. planning it out after i had an intial plan
    - was mostly good think it maybe went into too much detail for version 1
    - got some things i hadnt considered
3. bash scripting, for any bash scripts primary/secondary/testing
4. q usage
    - simpler tasks eg. creating tables
    - used it in the spawning functionality for spawning secondaries from the primary and the testing
    Worked well mostly with a couple of style fixes (reordering so less brackets) and redefining variable names eg. in qspec it used `before` as a variable and had used `value` in another instance



# my notes ignroe in any PR reviews till the end

```
jrutledge@homer:~/internalWork/Parallelisation-Project$ bash bin/startprimary.sh

start primary: port 45000, config config/default.env
startprimary: port 45000, config config/default.env, pid 1362094, log logs/primary.2026.10.05D13.29.29.log

jrutledge@homer:~/internalWork/Parallelisation-Project$ bash bin/startsecondary.sh 1
start secondary: id 1, port 45001, config config/default.env, pid 1362384, log logs/sec1.2026.10.05D13.29.34.log

jrutledge@homer:~/internalWork/Parallelisation-Project$ bash bin/startsecondary.sh 2
start secondary: id 2, port 45002, config config/default.env, pid 1362708, log logs/sec2.2026.10.05D13.29.37.log
jrutledge@homer:~/internalWork/Parallelisation-Project$ 
```

### q stuff
```q
pri:hopen `::45000

sec1:hopen `::45001
```
### create an images folder or stick them all under docs/images and look at referncing them better
![alt text](image.png)


## info on kernal memory
We can see the kernal mem stats at `/proc/<pid>/status` file

**VmRSS**: Resident memory, this is all the physical RAM a process occupies. Its is roughly `RssAnon + RssFile`.

**RssAnon**: RAM not backed by a file. For q essentially the heap pages actually in use. The kernal cannot drop it so its the memory that leads to swapping or the OOM killer. In q the `heap` is what has been promised and available but `RssAnon` is what the kernal has promised, so usually the `heap > RssAnon`.

**RssFile**: RAM holding file page eg. q binary, libs and mapped files. The kernal can drop and read it from disk again so it is not a real cost. This is different to `mmap` in q as this is only files q mapped where as `RssFile` has the binarys and libs.

**VmHWM**: The largest `VmRSS` has been since the process has started or the last reset. (this can be done by writing `5` to `/pric/<pid>/clear_refs`)

We are using these instead of `.Q.w[]` as we can read `/proc/<pid>/status` at any time and `RSS` is what the kernal enforces.


Too test `OOM` i might need to use `cgroups` this allows me to allocate a certain amount of RAM to my processes so they will be chosen to kill first if mem limits are reached

Claude steps

## Testing out-of-memory safely on homer (cgroups)

homer is shared, so anything that might run out of memory runs inside a **cgroup (control group)** with its own memory limit. When the limit is reached, the kernel kills a process **inside the cgroup** (a secondary, as they set `oom_score_adj=1000`) and nothing outside it is affected. Always use `MemorySwapMax=0`: homer already uses a lot of swap, and without it a cgroup at its limit would swap instead of being killed.

`systemd-run` doesn't know shell aliases, so use the full path to q (`$KDBX_HOME/bin/q`), not `x`.

To do this we edit the file `/proc/<pid>/cgroup` by changing the start to use `/sys/fs/cgroup`. This can be seen in the function `.cgroup.dir`.

In the files under our cgroup directory we have the following;
```bash
d=<cgroup_dir>
cat $d/memory.current      # bytes the whole cgroup is using right now (all its processes together)
cat $d/memory.max          # the limit: "max" means no limit
cat $d/memory.events       # counters: how often the limit was hit, and oom_kill
cat $d/cgroup.procs        # the pids in this cgroup
```

So we will edit the `memory.max` file, so every process started in the same cgroup will be subjected to this. Since we start the secondary processes from the primary they will be under the same cgroup. When `memory.current` reaches `memory.max` the kernal will look at which processes have the highest `oom_score` and kill them first. As we start all secondary processes with an `oom_score_adj`=1000 it kills secondary processes first. It will add 1 to `oom_kill` in that cgroups `memory.events`

### How does it decide which process to kill?

How bad a process is can be calculated
```bash
badness = the process's resident memory + its swap + its page tables      (in pages)
        + oom_score_adj × (total memory allowed ÷ 1000)
```

Which ever process has the highest `badness` will be killed first by the kernal.

### How to start the primary in a cgroup

```bash
cd ~/internalWork/Parallelisation-Project
set -a; source config/default.env; set +a
systemd-run --user --scope --unit=qfwoom -p MemoryMax=1G -p MemorySwapMax=0 $KDBX_HOME/bin/q src/primary.q -p 45000
```

### What the primary does when a secondary is killed for memory

At start the primary finds its cgroup (`/proc/<pid>/cgroup`) and remembers the
`oom_kill` count from that cgroup's `memory.events`. When a secondary's connection
closes, the primary reads the count again. If it has gone up, the secondary was
killed by the kernel: its task is marked `failed` with reason `oom` and is **not**
retried (`oom` is not in `RETRY_REASONS`), because it would only be killed again.
Otherwise the reason is `lost` and the task is retried as usual. Either way the
secondary is restarted (up to `RESPAWN_MAX`).

Outside a memory-limited cgroup the count stays 0, so every death is `lost`.

To see it happen:

```bash
set -a; source config/default.env; set +a
systemd-run --user --scope --unit=qfwoom -p MemoryMax=1G -p MemorySwapMax=0 $KDBX_HOME/bin/q src/primary.q -p 45000
```
```q
q)t:.primary.newtask `tasktype`args!(`hold;`mb`secs!(1500;10))
q)tasks[t]`state`reason`retrycount        / `failed`oom, 0i
q)system "cat ",.primary.cgroupdir,"/memory.events"   / oom_kill 1
q).primary.showstatus[]                   / that secondary is back, restarts 1
```
Always set `MemorySwapMax=0`: without it the kernel swaps the process instead of
killing it, and homer already uses a lot of swap.


# Demo

1. show how to start with cgroups
```bash
set -a; source config/default.env; set +a
systemd-run --user --scope -p MemoryMax=$GLOBAL_MEM_LIMIT -p MemorySwapMax=0 $KDBX_HOME/bin/q src/primary.q -p 45000
# systemd-run --user --scope         # run a command in a new cgroup of its own
# -p MemoryMax=$GLOBAL_MEM_LIMIT     # the hard cap: the kernel kills inside this cgroup above 4GB
# -p MemorySwapMax=0                 # kill rather than swap
# $KDBX_HOME/bin/q                   # it has to be the full path as systemd-run can't see the x alias
```
```q
.primary.cgroupdir                                    / the cgroup the primary and secondaries are in
system "cat ",.primary.cgroupdir,"/memory.max"        / 4294967296: the kernel's cap
.primary.showstatus[]                                 / 8 secondaries, all free
```

2. do a comparison between 8 secondaries and 8 threads for the same query
```bash
# in a different terminal run
cd ~/internalWork/Parallelisation-Project
set -a; source config/default.env; set +a
x src/approvedtasks.q -s 8
```
Then
```q
// load in the hdb
\l /home/jrutledge/internalWork/hdb

// check the number of dates
count date

// check our function exists
.task.vwap

// time how long it takes
start:.z.P; raze .task.vwap peach date ; .z.P-start
// 0D00:00:09.232734870

// cache loaded in
start:.z.P; raze .task.vwap peach date ; .z.P-start
// 0D00:00:00.770165808
```
Now connect to the primary
```q
// connect to the primary
h:hopen 45000

// check the approved functions
h".primary.tasktypes"

// show a bad task: only approved task types can run, this is refused before anything is created
jobID:h(`.primary.newjob; `bad; date; ()!())

// run a good task: one job, one task per date, ()!() for no params
jobID:h(`.primary.newjob; `vwap; date; ()!())

// run this until it is done
h({jobs x}; jobID)

// time how long it took to run
h({exec finishedtime-submittedtime from jobs where jobid=x}; jobID)
start:.z.P; raze get each h(`.primary.jobpaths; jobID); .z.P-start
// 0D00:00:00.002124168

// compare results
(raze get each h(`.primary.jobpaths; jobID))~raze .task.vwap peach date
```

3. show the mem used for a single job before and after
```q
// check the mem for each task in MB
h({select[10] taskid, before:`long$membefore%1048576, peak:`long$memafter%1048576, aftergc:`long$memaftergc%1048576 from tasks where jobid=x}; jobID)

// a job that uses 300MB per task, to make it obvious
jm:h(`.primary.newjob; `hold; 8#enlist `mb`secs!(300;1); ()!())
h({select taskid, before:`long$membefore%1048576, peak:`long$memafter%1048576, aftergc:`long$memaftergc%1048576 from tasks where jobid=x}; jm)
/ every task: about 2MB before, about 300MB peak, back to about 2MB after the gc
```

4. show how to run high priority jobs
```q
// a long job: 40 tasks of 3 seconds on 8 secondaries, so most of it is queued, priority 0
jl:h(`.primary.newjob; `sleep; 40#3; ()!())

// an urgent job, submitted after it, priority 10
ju:h(`.primary.newjob; `sumtil; 1000 2000 3000; ([priority:10]))

// run on primary, both jobs and their priorities
select jobid, priority, state, submittedtime, finishedtime from jobs
```

5. show dispatch pausing above the memory cap and resuming below it
```q
// soft cap down to 2GB; the kernel's hard cap stays at 4GB
h".primary.memcap:2147483648"

// 16 tasks of 300MB, held for 2 to 9 seconds
jg:h(`.primary.newjob; `hold; ([] mb:16#300; secs:16#2 3 4 5 6 7 8 9); ()!())

// in the primary's terminal, every second or two: the dispatch line shows PAUSED, then running
.primary.showstatus[]

// how many times it paused, and for how long
.primary.status[]`dispatch

// soft cap back to 4GB
.primary.memcap:4294967296
```

6. show jobs failing, and what the framework does about it

6.1 a task that throws an error: reported, not retried, the job fails
```q
je:h(`.primary.newjob; `fail; enlist 0; ()!())
h({select taskid, state, reason, err, retrycount from tasks where jobid=x}; je)
```

6.2 a timeout: this job has a 5 second timeout, the secondary is killed and restarted, we give it a sleep 20 so it will timeout. Look at the secondaries start time
```q
.primary.tasktimeout
jt:h(`.primary.newjob; `sleep; enlist 20; ([timeout:00:00:05.000]))
h({select taskid, state, reason, err, retrycount from tasks where jobid=x}; jt)   / after 5s: timeout 
```

6.3 out of memory: one part asks for 5GB, over the kernel's 4GB cap
```q
jo:.primary.newjob[`hold; ([] mb:(3#100),5000,8#100; secs:12#5); ()!()]
select taskid, state, reason from tasks where jobid=jo            / part 4 oom, parts 9-12 cancelled, the rest done
system "cat ",.primary.cgroupdir,"/memory.events"                 / oom_kill 1
```

6.4 a secondary crashing mid-task: its task is retried, the job still finishes
```q
jk:.primary.newjob[ `sleep; 16#3; ()!()]; p:first exec pid from secondaries where status=`busy; system "kill -9 ",string p
select taskid, state, retrycount from tasks where jobid=jk
```

after 6.2, 6.3 and 6.4, in the primary's terminal: the killed secondary is back with a new pid and restarts 1
```q
.primary.showstatus[]
```

7. show where the results are, and that they don't need the primary
```q
h(`.primary.jobpaths; jobID)          / one file per task, in task order
h({jobs x}; jobID)                    / resultbytes: the total size before you load it
paths:h(`.primary.jobpaths; jobID)
```
stop the primary (\\ in its terminal), then:
```q
(raze get each paths)~raze .task.vwap peach date      / 1b: the results don't need the primary
```

8. Talking points (no commands)
- Why not -w:
  - it's per process, not one global cap;
  - it counts q's heap, not what the kernel enforces;
  - '-w abort can't be trapped, and takes every thread's work with it;
  - a cgroup gives one hard cap, real RSS, and a labelled oom.
- Soft cap vs hard cap: running tasks overshoot the soft cap, and the cgroup also counts the HDB's page cache. So in real use the hard cap should sit above the soft cap. Section 5 shows why.
- Priority: every task of a job carries the job's priority; dispatch sends the highest first, then the oldest. A running task is never interrupted, and there's no ageing yet, so a steady stream of urgent work could starve priority 0.

9. What's next
- From the brief, not done yet:
  - V2 scheduler: only send a task if its expected size (from the peaks recorded per task type) fits in the headroom left, thinking of doing this with a tasks compairson of peak mem used for same types of tasks
  - backoff on retries, and quarantine for a secondary that keeps failing
  - integration tests for the brief's list: happy path, gating, timeout, gc
- Building on what's there:
  - one blocking call that waits for a job and returns its paths (deferred reply)
  - memory per job on the jobs table: its footprint and its biggest task
  - a soft cap below the hard cap in the start scripts
  - fairness for priorities: ageing, so low-priority work can't be starved
  - cheaper /proc reads, and a retention policy for old results
  - the 30GB run
- Bigger steps:
  - secondaries on other machines
  - starting more secondaries when the queue is deep and there's memory to spare
  - packaging as a di.parallel module


## To Do

1. add in the global mem cap limit and test with 30GB
2. add deferred sync so when i run a job form another processes it will block the user until the job is complete
3. a tidy up of the code (mix of 4 and before dict usages), probably stick things in separate scripts where possible. Can probably get rid of alot of columns that i dont think i need anymore as well like start/registered time in the secondaries
4. change the log timestamps to be local time instead of utc, dont know if that is possible since we use a module
5. fix the start bash scripts to use the mem cap limit and start with a cgroup
6. Tidy up the readme
7. add a function to calcualte the mem used for a job and maybe store that data in the jobs table
8. do we need to run dispatch on a timer does it do naything? Yes for when a secondary crashes with an OOM failure so it can pick up tasks after a restart. It also picks up free tasks if the mem limit is hit once that task is done

 