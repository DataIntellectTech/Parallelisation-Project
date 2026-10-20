// this is the primary process that monitors secondaries and assigns tasks
// start from top level dir with 
// q src/primary.q -p 45000

// load in schema
system"l schemas/primarytables.q";

// load in common code libs
// todo: change this in the future to load in the entire common code or all files with an each
// also look at resolving the dir name for a full file path use an env var in the config file
system"l src/common/log.q";
system"l src/common/timer.q";
system"l src/common/os.q";

// get env vars
.primary.stale:00:00:00.001*"J"$getenv`STALE_MS;
.primary.heartbeat:00:00:00.001*"J"$getenv`HEARTBEAT_MS;
.primary.spawnsecondaries:"B"$getenv`SPAWN_SECONDARY;
.primary.numsecondaries:"J"$getenv`NUM_SECONDARYS;
.primary.baseport:"J"$getenv`SECONDARY_BASE_PORT;
.primary.stopgraceperiod:"J"$getenv`STOP_GRACE_PERIOD_SECS;
.primary.logdir:getenv`LOG_DIR;
.primary.qbin:getenv[`KDBX_HOME],"/bin/q";
.primary.starttime:0Np;
.primary.secondarystates:`free`busy`stale`closed;
.primary.taskstates:`queued`dispatched`running`done`failed;
.primary.tasktimeout:`time$"J"$getenv `TASK_TIMEOUT_MS;
.primary.taskretries:"I"$getenv`TASK_RETRIES_MAX;
.primary.tasktypes:`$"," vs getenv`TASK_TYPES;
.primary.lasttaskid:0;



// dict of secondaries ids to their pids that the primary started
.primary.spawned:(`long$())!`int$();

// defaults for the optional task fields, newtask fills any missing field from here
.primary.taskdefaults:([priority:0i; memestimate: 0N; timeout: .primary.tasktimeout; retriesmax: .primary.taskretries]);

// what each task status can move too
.primary.taskchange:([queued: enlist `dispatched; dispatched: `running`failed; running: `done`failed; done:`$(); failed:enlist `queued]);

// the time column that gets updated at each task status
.primary.statustime:([dispatched: `dispatchedtime; running: `startedtime; done: `finishedtime; failed: `finishedtime]);




// when a secondary starts add it to the secondaries table
// example run:
// .primary.register ([id:5; pid:4000i; host:`localhost; port:45001i ])
.primary.register:{[info]
  `secondaries upsert (info`id; .z.w; info`pid; info`host; info`port; `free; .z.P; 0N; 0Ni; 1b; info[`id] in key .primary.spawned; .z.P; .z.P; (); 0N);
  .log.info "secondary ", string[info`id], " registered at: ", string .z.P;
 };

// to be called by each secondary except when its status is running, ran based off HEARTBEAT_MS
.primary.heartbeatcheck:{[mem]
  update lastheartbeat:.z.P, lastmembytes: mem, status: `free from `secondaries where handle=.z.w;
 };

// mark secondaries that arent sedning updates as stale
.primary.check:{
  if[not count secondaries; :()];
  stale: exec id from secondaries where status=`free, lastheartbeat < .z.P - .primary.stale;
  if[count stale;
    update status:`stale from `secondaries where id in stale;
    .log.warn "no heartbeat from secondary ",(", " sv string stale)];
 };


// how many of each state appear in the status col, done like this so can have 0 for failed say if no failed in the status col
.primary.countby:{[states;statuscol] states!sum each statuscol=/:states};

// a snapshot of the primarys status
.primary.status:{
  secs:select id, pid, port, status, spawned, lastseen:`time$.z.P-lastheartbeat,lastmembytes from 0!secondaries;
  ([time: .z.P; uptime: .z.P-.primary.starttime; secondaries: secs; seccounts: .primary.countby[.primary.secondarystates;exec status from secondaries]; taskcounts: .primary.countby[.primary.taskstates;exec state from tasks]])
 };

// the same snapshot, printed for a person at the console
.primary.showstatus:{
  pristatus:.primary.status[];
  fmt:{[d] ", " sv {[d;k] string[d k]," ",string k}[d] each key d};
  -1 "== primary status ",string[pristatus`time],"  uptime ",string[pristatus`uptime]," ==";
  -1 "secondaries: ",fmt pristatus`seccounts;
  show pristatus`secondaries;
  -1 "tasks: ",fmt pristatus`taskcounts;
 };

// command line for secondary n, e.g. /opt/kdbx/.../q src/secondary.q -p 45002 -id 2
// look at wrapping in protected execution
.primary.spawncmd:{[n]
  " " sv (.primary.qbin; "src/secondary.q"; "-p"; string .primary.baseport+n-1; "-id"; string n)
 };

// ids taken right now: registered and still connected, or spawned by this primary and still running
.primary.usedids:{
  exec id from secondaries where status<>`closed
 };

// the lowest id not in use, e.g. 3 when 1, 2 and 4 are taken
.primary.nextid:{
  ids:.primary.usedids[];
  min (1+til 1+count ids) except ids
 };

// bring up a secondary with a given id
// example uage:
// .primary.spawn 1
.primary.spawn:{[n]
  if[n in .primary.usedids[];
    .log.warn "secondary ",string[n]," already exists; next available id is ",string .primary.nextid[];
    :()];
  .os.mkdir .primary.logdir;
  logfile:.primary.logdir,"/sec",string[n],".",ssr[19#string .z.P;":";"."],".log";
  startcmd:.primary.spawncmd[n]," < /dev/null >> ",logfile," 2>&1 & echo $!";
  pid:"I"$first system startcmd;
  .log.info "running system command: ", startcmd;
  .primary.spawned[n]:pid;
  .log.info "spawned secondary ",string[n]," (pid ",string[pid],") on port ",string .primary.baseport+n-1;
 };

// used to shut down all spawned secondaries
.primary.stop:{
  .log.info "stopping secondaries";
  handles:exec handle from secondaries where not null handle, not status=`closed;
  {[h] @[neg[h];(`.secondary.stop;::);{[e] ::}]} each handles;   /// no stop sec func on sec.q script
  .os.sleep .primary.stopgraceperiod;
  left:p where .os.exists each "/proc/",/:string p:value .primary.spawned;
  if[count left;
    .log.warn "killing secondaries that didn't exit: pids ",", " sv string left;
    {[p] @[.os.kill9;p;{[e] ::}]} each left];
  .primary.spawned:(`long$())!`int$();
  .log.info "stopped";
 };

// tasks will only ever go up
.primary.nexttaskid:{
  .primary.lasttaskid+::1;
  .primary.lasttaskid
 };


// add a new tesk to the tasks table
// task is a dict with tasktype and args always required evry other col is optional 
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
    finishedtime:0Np; membefore:0N; memafter:0N; err:""; reason:`; result:enlist (::)]);
  `tasks upsert data;
  .log.info "new task ",string[tid]," ",string task`tasktype;
  tid
 };

// update task status using .primary.taskchange and .primary.statustime
// params allows us to update other columns eg. maxretires and retrycount
// if nothing for params it should be an empty dict
.primary.taskupdate:{[tid; newstate; params]
  if[not count exec taskid from tasks where taskid=tid; 
    .log.warn"the task id ",string[tid]," is not present in the tasks table";
    :0b];
  oldstate: first exec state from tasks where taskid=tid;
  if[not newstate in .primary.taskchange oldstate; 
    .log.warn"the new task state ",string[newstate]," is not a valid option choose on of the following: ",", " sv string .primary.taskchange oldstate;
    :0b];
  timecol: $[newstate in key .primary.statustime; (enlist .primary.statustime newstate)!enlist .z.P; ()!()];
  params: params, timecol, ([taskid: tid; state: newstate]);
  .log.info "updating task id ",string[tid]," from ",string[oldstate]," to ",string newstate;
  upsert[`tasks; params];
  .log.info "updated task id ",string[tid]," from ",string[oldstate]," to ",string newstate;
  if[newstate in `done`failed;
    sid:first exec secondaryid from tasks where taskid=tid;
    update status:`free, currenttask:0N from `secondaries where id=sid, currenttask=tid, status=`busy];
  1b
 };

// sends the task to the secondary, if sending fails early exit and mark as stale
.primary.sendtask:{[sid; tid]
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
  .log.info "sent task ",string[tid]," to secondary ",string[sid]," to run task ",string t`tasktype;
 };

// hand a queued task to a secondary, do it by priority then by oldest first
// will run on a timer every 1 sec
.primary.dispatch:{
  // check for free secondaries
  freesec: exec id from secondaries where status=`free;
  // if none free exit
  if[not count freesec; :()];
  // get queued tasks
  qtasks: exec taskid from `priority xdesc select taskid, priority from 0!tasks where state=`queued;
  // if no tasks exit early
  n:min count[freesec], count qtasks;
  if[n=0; :()];
  // get teh min of both tasks and free secs then run .primary.sendtask for each combo available
  .primary.sendtask'[n#freesec; n#qtasks];
 };

// if a connection is close we need to mark it as closed
.z.pc:{[h]
  secid: first exec id from secondaries where handle=h;
  tid: first exec currenttask from secondaries where id=secid;
  update status:`closed, handle:0Ni, currenttask: 0N from `secondaries where id=secid;
  .log.info "secondary ",string[secid]," has closed its connection to the primary";
  if[not null tid;
    .primary.taskupdate[tid; `failed; ([err:"secondary lost"; reason:`lost])];
    .log.warn "task ",string[tid]," was on secondary ",string[secid],", marking it as failed"];
 };

// quitting the primary kills any spawned secondaries
.z.exit:{ if[count .primary.spawned; .primary.stop[]]};

// start sequence
.primary.start:{
  if[.primary.spawnsecondaries; .primary.spawn each 1+til .primary.numsecondaries];
  .timer.addjob.custom[`stalecheck; {.primary.check[]}; (); 1; 2; ()!()];
  .timer.addjob.custom[`dispatch; {.primary.dispatch[]}; (); 1; 2; ()!()];
  .log.info "primary started, listening on ",string system "p";
  .primary.starttime:: .z.P;
 };

// start primary
.primary.start[];