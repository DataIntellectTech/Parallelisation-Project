// this is the primary process that monitors secondaries and assigns tasks
// start from top level dir with
// x src/primary.q -p 45000

// load in schema
system"l schemas/primarytables.q";

// load in common code libs
// todo: change this in the future to load in the entire common code or all files with an each
// also look at resolving the dir name for a full file path use an env var in the config file
system"l src/common/log.q";
system"l src/common/timer.q";
system"l src/common/os.q";
system"l src/common/mem.q";
system"l src/common/cgroup.q";

// get env vars and set intial value for variables
.primary.starttime:0Np;
.primary.stale:00:00:00.001*"J"$getenv`STALE_MS;
.primary.heartbeat:00:00:00.001*"J"$getenv`HEARTBEAT_MS;
.primary.logdir:getenv`LOG_DIR;
.primary.spawnsecondaries:"B"$getenv`SPAWN_SECONDARY;
.primary.numsecondaries:"J"$getenv`NUM_SECONDARYS;
.primary.stopgraceperiod:"J"$getenv`STOP_GRACE_PERIOD_SECS;
.primary.qbin:getenv[`KDBX_HOME],"/bin/q";
.primary.secondarythreads:1|"J"$getenv`THREADS;
.primary.tasktimeout:`time$"J"$getenv `TASK_TIMEOUT_MS;
.primary.taskretries:"I"$getenv`TASK_RETRIES_MAX;
.primary.tasktypes:`$"," vs getenv`TASK_TYPES;
.primary.lasttaskid:0;
.primary.resultsroot:getenv `RESULTS_DIR;
.primary.memhistorymax:"J"$getenv`MEM_HISTORY_MAX;
.primary.selfmem:0N;                               // the primary's own rssanon, bytes, from the last poll
.primary.memcap:"J"$getenv`GLOBAL_MEM_LIMIT;       // the global cap in bytes
.primary.paused:0b;                                // is dispatching new tasks held back by the mem cap
.primary.pausedsince:0Np;                          // when the current pause started
.primary.pausedtotal:0D;                           // total time spent paused
.primary.pausecount:0;                             // how many times dispatch has paused


// dict of secondaries ids to their pids that the primary started
.primary.spawned:(`long$())!`int$();

// defaults for the optional task fields, newtask fills any missing field from here
.primary.taskdefaults:([priority:0i; memestimate: 0N; timeout: .primary.tasktimeout; retriesmax: .primary.taskretries]);

// what each task status can move to
.primary.taskchange:([queued: `dispatched`failed; dispatched: `running`failed; running: `done`failed; done:`$(); failed:enlist `queued]);

// the time column that gets updated at each task status
.primary.statustime:([dispatched: `dispatchedtime; running: `startedtime; done: `finishedtime; failed: `finishedtime]);

// when a secondary starts add it to the secondaries table
// example run:
// .primary.register ([id:5; pid:4000i; host:`localhost])
.primary.register:{[info]
  `secondaries upsert ([id: info`id; handle: .z.w; pid: info`pid; host: info`host; status: `free;
    lastheartbeat: .z.P; consecutivefails: 0i; healthy: 1b; spawned: info[`id] in key .primary.spawned;
    starttime: .z.P; registeredtime: .z.P; tasktypes: (); currenttask: 0N; rssanon: 0N; vmrss: 0N; memtime: 0Np]);
  .log.info "secondary ", string[info`id], " registered at: ", string .z.P;
  .primary.resultsdir
 };

// called by each secondary to let the primary know it is not idle
// called from the secondary like:
// neg[.secondary.handle](`.primary.heartbeatcheck; .secondary.rssanon[])
.primary.heartbeatcheck:{[mem]
  update lastheartbeat:.z.P, rssanon:mem, memtime:.z.P from `secondaries where handle=.z.w;
  update status:`free from `secondaries where handle=.z.w, status=`stale;
 };

// mark secondaries that arent sending updates as stale
.primary.check:{
  if[not count secondaries; :()];
  stale: exec id from secondaries where status=`free, lastheartbeat < .z.P - .primary.stale;
  if[count stale;
    update status:`stale from `secondaries where id in stale;
    .log.warn "no heartbeat from secondary ",(", " sv string stale)];
 };

// used to start a secondary process
.primary.spawncmd:{
  " " sv (.primary.qbin; "src/secondary.q"; "-id"; string x; "-s"; string .primary.secondarythreads)
 };

// ids taken right now: registered and still connected
.primary.usedids:{
  exec id from secondaries where status<>`closed
 };

// the lowest id not in use, e.g. 3 when 1, 2 and 4 are taken
.primary.nextid:{
  ids:.primary.usedids[];
  min (1+til 1+count ids) except ids
 };

// bring up a secondary with a given id
// example usage:
// .primary.spawn 1
.primary.spawn:{
  if[x in .primary.usedids[];
    .log.warn "secondary ",string[x]," already exists; next available id is ",string .primary.nextid[];
    :()];
  .os.mkdir .primary.logdir;
  logfile:.primary.logdir,"/sec",string[x],".",ssr[19#string .z.P;":";"."],".log";
  startcmd:.primary.spawncmd[x]," < /dev/null >> ",logfile," 2>&1 & echo $!";
  pid:"I"$first system startcmd;
  .log.info "running system command: ", startcmd;
  .primary.spawned[x]:pid;
  .log.info "spawned secondary ",string[x]," , pid ",string pid;
 };

// used to shut down all spawned secondaries
// used when the primary is shut down to stop any secondaries it started
.primary.stop:{
  .log.info "stopping secondaries";
  handles:exec handle from secondaries where not null handle, not status=`closed;
  {[h] @[neg[h];(`.secondary.stop;::);{[e] ::}]} each handles;
  .os.sleep .primary.stopgraceperiod;
  left:p where .os.exists each "/proc/",/:string p:value .primary.spawned;
  if[count left;
    .log.warn "killing secondaries that didn't exit: pids ",", " sv string left;
    {[p] @[.os.kill9;p;{[e] ::}]} each left];
  .primary.spawned:(`long$())!`int$();
  .log.info "stopped";
 };

// keep track of task ids
.primary.nexttaskid:{
  .primary.lasttaskid+::1;
  .primary.lasttaskid
 };

// add a new task to the tasks table
// task is a dict with tasktype and args always required every other col is optional
// example run:
// .primary.newtask ([tasktype:`sumtil; args:1000])
.primary.newtask:{[task]
  if[not 99h=type task;
    .log.warn "newtask: a task must be a dict"; :0N];
  if[not all `tasktype`args in key task;
    .log.warn "newtask: tasktype and args are required"; :0N];
  if[not task[`tasktype] in .primary.tasktypes;
    .log.warn "newtask: unknown task type ",string task`tasktype; :0N];  // this can be rejected here before it gets to a secondary
  if[count bad:key[task] except `tasktype`args,key .primary.taskdefaults;
    .log.warn "newtask: unknown fields ",", " sv string bad; :0N];
  tid:.primary.nexttaskid[];
  data:.primary.taskdefaults,task,
    ([taskid:tid; args:enlist task`args; submittedtime:.z.P; retrycount:0i; state:`queued; secondaryid:0N; dispatchedtime:0Np; startedtime:0Np;
    finishedtime:0Np; membefore:0N; memafter:0N; memaftergc:0N; err:""; reason:`; resultpath:`; resultbytes:0N; jobid:0N; user:`]);
  `tasks upsert data;
  .log.debug "new task ",string[tid]," ",string task`tasktype;
  tid
 };

// update task status using .primary.taskchange and .primary.statustime
// params allows us to update other columns eg. retriesmax and retrycount
// if nothing for params it should be an empty dict
.primary.taskupdate:{[tid; newstate; params]
  if[null tasks[tid]`state; 
    .log.warn"the task id ",string[tid]," is not present in the tasks table";
    :0b];
  oldstate: tasks[tid]`state;
  if[not newstate in .primary.taskchange oldstate; 
    .log.warn"the new task state ",string[newstate]," is not a valid option, choose one of the following: ",", " sv string .primary.taskchange oldstate;
    :0b];
  timecol: $[newstate in key .primary.statustime; (enlist .primary.statustime newstate)!enlist .z.P; ()!()];
  params: params, timecol, ([taskid: tid; state: newstate]);
  upsert[`tasks; params];
  .log.info "updated task id ",string[tid]," from ",string[oldstate]," to ",string newstate;
  if[newstate in `done`failed;
    sid:tasks[tid]`secondaryid;
    update status:`free, currenttask:0N, lastheartbeat:.z.P from `secondaries where id=sid, currenttask=tid, status=`busy;
    // Claude as part of bench-401
    // the secondary has just given its memory back (.Q.gc[]): use its own after-gc figure until the next poll,
    // so dispatch sees the freed memory straight away instead of the last poll's reading
    if[`memaftergc in key params;
      if[not null params`memaftergc; update rssanon:params`memaftergc from `secondaries where id=sid]]];
  //if[newstate=`failed; .primary.retry tid]; // will add once we add in retry logic
  //if[newstate in `done`failed; .primary.jobcheck tid]; // will add in once adding jobs bit
  if[newstate in `done`failed; .primary.dispatch[]];  // prevents us waiting on the timer, when bench marking this was the biggest this was biggest bottleneck so added it
  1b
 };

// sends the task to the secondary, if sending fails early exit and mark as stale
.primary.sendtask:{[sid; tid]
  if[not (`free~secondaries[sid]`status) and `queued~tasks[tid]`state; :()];
  h:first exec handle from secondaries where id=sid;
  t:tasks tid;
  update status:`busy, currenttask:tid from `secondaries where id=sid;
  .primary.taskupdate[tid; `dispatched; ([secondaryid: sid])];
  res:@[neg[h]; (`.secondary.runtask; tid; t`tasktype; first t`args); {[error] (`sendfailed; error)}];
  if[`sendfailed~ first res;
    .log.warn "cannot send task ",string[tid]," to secondary ",string sid;
    update status:`stale, currenttask: 0N from `secondaries where id=sid;
    :.primary.taskupdate[tid; `failed; ([err:"send failed with error: ",last res; reason:`sendfailed])];
   ];
  .log.info "sent task ",string[tid]," (",string[t`tasktype],") to secondary ",string sid;
 };

// hand a queued task to a secondary, do it by priority then by oldest first
// nothing new runs when total mem is over the cap
// will run on a timer every 1 sec
.primary.dispatch:{
  freesec: exec id from secondaries where status=`free;
  if[not count freesec; :()];
  qtasks: exec taskid from `priority xdesc 0!select taskid, priority from tasks where state=`queued;
  if[not count qtasks; :()];
  if[.primary.overcap[]; :()];
  //qtasks:.primary.fit[qtasks; count freesec]; // will add in once we add in mem cap logic
  n:min count[freesec], count qtasks;
  .primary.sendtask'[n#freesec; n#qtasks];
 };

// Claude with minor edits from me
// read our own memory and every live secondary's from /proc in one call, store it, and add a history row
// works for busy secondaries too: nothing is asked of them. A pid that has gone gets nulls until .z.pc closes it
.primary.pollmem:{
  m:.mem.read .z.i, exec pid from secondaries where status<>`closed;
  .primary.selfmem:first exec rssanon from m where pid=.z.i;
  ra:exec pid!rssanon from m;
  rs:exec pid!vmrss from m;
  update rssanon:ra pid, vmrss:rs pid, memtime:.z.P from `secondaries where status<>`closed;
  sec:exec sum rssanon from secondaries where status<>`closed;
  `memhistory insert (.z.P; .primary.selfmem+sec; .primary.selfmem; sec; exec `int$count i from secondaries where status=`busy);
  if[.primary.memhistorymax<n:count memhistory; delete from `memhistory where i<n-.primary.memhistorymax];
 };

// Claude with minor edits from me
// bytes as whole MB, for logs
.primary.mb:{string[`long$x%1048576],"MB"};

// Claude with minor edits from me
// total memory in use: the primary plus every live secondary, from the last poll, in bytes
.primary.totalmem:{.primary.selfmem + exec sum rssanon from secondaries where status<>`closed};

// Claude with minor edits from me
// 1b if dispatch should hold back because total memory is over the cap; logs and times each pause and resume
.primary.overcap:{
  if[null .primary.memcap; :0b];
  // the last poll can be up to a second old: if it says we're over, read again so a task that just finished counts
  if[.primary.memcap<.primary.totalmem[]; .primary.pollmem[]];
  tot:.primary.totalmem[];
  overcap:tot>.primary.memcap;
  if[overcap and not .primary.paused;
    .primary.paused:1b; .primary.pausedsince:.z.P; .primary.pausecount+:1;
    .log.warn "pausing dispatch: memory ",.primary.mb[tot]," is over the cap of ",.primary.mb .primary.memcap];
  if[.primary.paused and not overcap;
    .primary.paused:0b; .primary.pausedtotal+:.z.P-.primary.pausedsince;
    .log.info "resuming dispatch: memory ",.primary.mb[tot]," is under the cap of ",.primary.mb[.primary.memcap],", was paused for ",string .z.P-.primary.pausedsince];
  overcap
 };


// if a secondary loses connection mark it as closed
.z.pc:{[h]
  secid: first exec id from secondaries where handle=h;
  if[null secid; :()];
  tid: first exec currenttask from `secondaries where id=secid;
  update status:`closed, handle:0Ni, currenttask: 0N from `secondaries where id=secid;
  .log.info "secondary ",string[secid]," has closed its connection to the primary";
  if[not null tid;
    r:([err:"secondary lost"; reason:`lost]);
    .primary.taskupdate[tid; `failed; r];
    .log.warn"task ",string[tid]," was on secondary ",string[secid]," marking it as failed due to ",string r`reason;
   ];
 };

// quitting the primary kills any spawned secondaries
.z.exit:{ if[count .primary.spawned; .primary.stop[]]};


// start sequence
.primary.start:{
  .primary.starttime:: .z.P;
  if[not count .primary.resultsroot; '"RESULTS_DIR is not set"];
  .primary.resultsdir::.primary.resultsroot,"/",ssr[string .primary.starttime;":";"."];
  .os.mkdir .primary.resultsdir;
  .log.info "task results will be saved in ",.primary.resultsdir;
  if[.primary.spawnsecondaries; .primary.spawn each 1+til .primary.numsecondaries];
  .timer.addjob.custom[`stalecheck; {.primary.check[]}; (); 1; 2; ()!()];
  .timer.addjob.custom[`dispatch; {.primary.dispatch[]}; (); 1; 2; ()!()];
  .timer.addjob.custom[`mempoll; {.primary.pollmem[]}; (); 1; 2; ()!()];
  .log.info "primary started, listening on ",string system "p";
 };

// start primary
.primary.start[];


select id, status, rssanon from secondaries
-1#memhistory
tasks h
select id, status, rssanon from secondaries
