# Jobs and Tasks

## Jobs
These are split into tasks

Include
1. how to run a job
2. how to get results

## Tasks
A task is a whitelisted function that is sent to a secondary process. We can send a task using the `.primary.newtask` function:
```q
.primary.newtask ([tasktype:`sumtil; args:1000])
```
We can also add in extra optional fields 
| Field | Default | Meaning |
|---|---|---|
| `priority` | 0 | higher is sent first |
| `timeout` | `TASK_TIMEOUT_MS` | how long the task may run |
| `retriesmax` | `TASK_RETRIES_MAX` | how many times it may be retried |
| `memestimate` | null | the memory it's expected to use |

When all secondaries are busy, tasks are marked as queued and will be executed on a first come first server basis unless it has a higher prioirty than other tasks in the queue

### Running Tasks
1. Normal task
```q
.primary.newtask[tasktype:` sumtil; args: 1000]
```

2. Run multiple tasks at once
```q
.primary.newtask each {([tasktype:`sleep; args:x])} each 10#2
```

3. Run a task as high priority
```q
// we have 4 secondaries so lets make everything busy
.primary.newtask each {([tasktype:`sleep; args:x])} each 4#5

//send a low and high priority task
low:.primary.newtask ([tasktype:`sleep; args:1]); high:.primary.newtask ([tasktype:`sleep; args:1; priority:10i])

// we can see the high task was dispatched first
select taskid, priority, dispatchedtime from tasks where taskid in (low,high) 
taskid priority dispatchedtime               
---------------------------------------------
16     0        2026.11.05D11:52:33.540859541
17     10       2026.11.05D11:52:33.539729147
```

### Tasks Results
Results of a task are saved at `RESULTS_DIR/<primary start time>/<taskid>`, before its `.Q.gc[]`. Only the path and size go back to the primary, in `resultpath` and `resultbytes`, so results never pass through the primary's memory. 
You can get a tasks result using the below
```q
get tasks[1]`resultpath  // 1 is the taskid
```

