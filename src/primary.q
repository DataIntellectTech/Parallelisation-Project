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
system"l src/common/mem.q";
system"l src/common/cgroup.q";

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
.primary.retryreasons:`$"," vs getenv `RETRY_REASONS;
.primary.memhistorymax:"J"$getenv`MEM_HISTORY_MAX;
.primary.selfmem:0N;         // the primary's own rssanon, bytes, from the last poll  // these are Claudes
.primary.memcap:"J"$getenv`GLOBAL_MEM_LIMIT;     // the global cap in bytes; null (unset or empty) = no cap
.primary.paused:0b;          // is dispatching new tasks held back by the mem cap
.primary.pausedsince:0Np;    // when the current pause started
.primary.pausedtotal:0D;     // total time spent paused
.primary.pausecount:0;       // how many times dispatch has paused
.primary.respawnmax:"J"$getenv`RESPAWN_MAX;   // how many times a spawned secondary is restarted after dying; 0 or null = never


// dict of secondaries ids to their pids that the primary started
.primary.spawned:(`long$())!`int$();

// defaults for the optional task fields, newtask fills any missing field from here
.primary.taskdefaults:([priority:0i; memestimate: 0N; timeout: .primary.tasktimeout; retriesmax: .primary.taskretries]);

// what each task status can move too
.primary.taskchange:([queued: enlist `dispatched; dispatched: `running`failed; running: `done`failed; done:`$(); failed:enlist `queued]);

// the time column that gets updated at each task status
.primary.statustime:([dispatched: `dispatchedtime; running: `startedtime; done: `finishedtime; failed: `finishedtime]);

// restarts so far, by secondary id
.primary.respawns:(`long$())!`long$();


// when a secondary starts add it to the secondaries table
// example run:
// .primary.register ([id:5; pid:4000i; host:`localhost; port:45001i ])
.primary.register:{[info]
  `secondaries upsert (info`id; .z.w; info`pid; info`host; info`port; `free; .z.P; 0N; 0Ni; 1b; info[`id] in key .primary.spawned; .z.P; .z.P; (); 0N; 0N; 0N; 0Np);
  .log.info "secondary ", string[info`id], " registered at: ", string .z.P;
 };

// to be called by each secondary except when its status is running, ran based off HEARTBEAT_MS
// CLAUDE: a heartbeat only brings a stale secondary back: it must never free a busy one, a heartbeat sent just
// before a task arrived can be processed after dispatch has marked it busy

.primary.heartbeatcheck:{[mem]
  update lastheartbeat:.z.P, lastmembytes: mem from `secondaries where handle=.z.w;
  update status:`free from `secondaries where handle=.z.w, status=`stale;
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
// memory is in bytes headroom how far under the cap we are
.primary.status:{
  secs:select id, pid, port, status, spawned, currenttask, rssanon, restarts:0^.primary.respawns id, lastseen:`time$.z.P-lastheartbeat, lastmembytes from 0!secondaries;
  tot:.primary.totalmem[];
  mem:([total:tot; cap:.primary.memcap; headroom:.primary.memcap-tot; primary:.primary.selfmem]);
  pt:.primary.pausedtotal+$[.primary.paused; .z.P-.primary.pausedsince; 0D];
  disp:([paused:.primary.paused; pausecount:.primary.pausecount; pausedtotal:pt; pausedsince:.primary.pausedsince]);
  ([time: .z.P; uptime: .z.P - .primary.starttime; memory: mem; dispatch: disp; secondaries: secs; seccounts: .primary.countby[.primary.secondarystates;exec status from secondaries]; taskcounts: .primary.countby[.primary.taskstates;exec state from tasks]])
 };

// the same snapshot, printed for a person at the console
.primary.showstatus:{
  pristatus:.primary.status[];
  fmt:{[d] ", " sv {[d;k] string[d k]," ",string k}[d] each key d};
  -1 "== primary status ",string[pristatus`time],"  uptime ",string[pristatus`uptime]," ==";
  m:pristatus`memory;
  -1 "memory: ",.primary.mb[m`total]," in use, ",$[null m`cap; "no cap"; .primary.mb[m`cap]," cap, ",.primary.mb[m`headroom]," headroom"];
  d:pristatus`dispatch;
  -1 "dispatch: ",$[d`paused; "PAUSED (memory over the cap) since ",string d`pausedsince; "running"],", paused ",string[d`pausecount]," times for ",string d`pausedtotal;
  -1 "secondaries: ",fmt pristatus`seccounts;
  show `id xasc select id, pid, port, status, spawned, task:currenttask, memmb:0.1*floor 0.5+10*rssanon%1048576, restarts, lastseen from pristatus`secondaries;
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
  if[newstate=`failed; .primary.retry tid];
  if[newstate in `done`failed; .primary.dispatch[]];  // prevents us waiting on the timer, when bench marking this was the biggest thi
  1b
 };

// sends the task to the secondary, if sending fails early exit and mark as stale
.primary.sendtask:{[sid; tid]
  if[not (`free~secondaries[sid]`status) and `queued~tasks[tid]`state; :()]; // double check if this is needed in testing remove it for a bit
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
  freesec: exec id from secondaries where status=`free;
  if[not count freesec; :()];
  qtasks: exec taskid from `priority xdesc select taskid, priority from 0!tasks where state=`queued;
  n:min count[freesec], count qtasks;
  if[n=0; :()];
  // the memory gate: send nothing new while total memory is over the cap
  if[.primary.overcap[]; :()];
  .primary.sendtask'[n#freesec; n#qtasks];
 };

// rerun a failed task or one where a secondary has died
.primary.retry:{[tid]
  t:tasks tid;
  if[not t[`reason] in .primary.retryreasons; :0b];
  if[t[`retrycount]>=t`retriesmax;
    .log.warn "task ",string[tid]," has used all ",string[t`retriesmax]," retries, leaving it failed";
    :0b];
  .log.info "retrying task ",string[tid],", retry ",string[1+t`retrycount]," of ",string t`retriesmax;
  .primary.taskupdate[tid; `queued; ([retrycount:1i+t`retrycount; secondaryid:0N; dispatchedtime:0Np; startedtime:0Np; finishedtime:0Np; membefore:0N; memafter:0N; err:""; reason:`])];
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

// claude minor edits
// bytes as whole MB, for logs
.primary.mb:{string[`long$x%1048576],"MB"};

// claude minor edits
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

// Claude with minor edits from me
// total memory in use: the primary plus every live secondary, from the last poll, in bytes
.primary.totalmem:{.primary.selfmem + exec sum rssanon from secondaries where status<>`closed};

// claude
// fail tasks that have run past their timeout. A busy secondary can't be interrupted, so its process is killed.
// Counts from startedtime, or dispatchedtime if the secondary never reported running
.primary.checktimeouts:{
  late:0!select taskid, secondaryid, timeout from tasks where state in `dispatched`running, .z.P>timeout + dispatchedtime^startedtime;
  if[not count late; :()];
  .primary.timeout'[late`taskid; late`secondaryid; late`timeout];
 };

//claude minor edits
// time out one task: take its secondary out of use and fail the task first, then kill the process.
// .z.pc fires once the process is dead, finds no task to fail as lost, and respawns the secondary
.primary.timeout:{[tid;sid;t]
  pid:first exec pid from secondaries where id=sid;
  .log.warn "task ",string[tid]," on secondary ",string[sid]," has run past its timeout of ",string[t],", killing pid ",string pid;
  update status:`closed, currenttask:0N from `secondaries where id=sid;
  .primary.taskupdate[tid; `failed; ([err:"timed out after ",string t; reason:`timeout])];
  @[.os.kill9; pid; {[e] .log.warn "could not kill secondary: ",e}];
 };

// restart a spawned secondary that has died capped with .primary.respawnsmax
.primary.respawnsecondary:{[sid]
  if[not sid in key .primary.spawned; :()];
  n:0^.primary.respawns sid;
  if[not n < .primary.respawnmax;
    .log.warn "secondary ",string[sid]," has been restarted ",string[n]," times already, max secondary restarts is ",string .primary.respawnmax;
    :()];
  .primary.respawns[sid]:n+1;
  .log.info "restarting secondary ",string[sid],", restart ",string[n+1]," of ",string .primary.respawnmax;
  .primary.spawn sid;
 };

// 1b if the kernel has killed a process in our cgroup for memory since we last checked, and count that kill as accounted for
// the kernel counts the kill before the connection close reaches us, so this is called from .z.pc
.primary.oomkilled:{
  n:.cgroup.oomkills .primary.cgroupdir;
  if[null n; :0b];
  if[n<=.primary.oomkills; :0b];
  .primary.oomkills+:1;
  1b
 };

// if a connection is close we need to mark it as closed
// we will now restart a secondary if it is closed and under .primary.respawnsmax
.z.pc:{[h]
  secid: first exec id from secondaries where handle=h;
  tid: first exec currenttask from secondaries where id=secid;
  update status:`closed, handle:0Ni, currenttask: 0N from `secondaries where id=secid;
  // was it killed by the kernel for memory? only check for secondaries, so other connections closing don't use up a kill
  oom:$[null secid; 0b; .primary.oomkilled[]];
  .log.info "secondary ",string[secid]," has closed its connection to the primary",$[oom; ": killed by the kernel for using too much memory"; ""];
  if[not null tid;
    r:$[oom; ([err:"secondary killed by the kernel for using too much memory"; reason:`oom]); ([err:"secondary lost"; reason:`lost])];
    .primary.taskupdate[tid; `failed; r];
    .log.warn "task ",string[tid]," was on secondary ",string[secid],", marking it as failed (",string[r`reason],")"];
  .primary.respawnsecondary secid;
 };

// quitting the primary kills any spawned secondaries
.z.exit:{ if[count .primary.spawned; .primary.stop[]]};

// start sequence
.primary.start:{
  if[.primary.spawnsecondaries; .primary.spawn each 1+til .primary.numsecondaries];
  .timer.addjob.custom[`stalecheck; {.primary.check[]}; (); 1; 2; ()!()];
  .timer.addjob.custom[`dispatch; {.primary.dispatch[]}; (); 1; 2; ()!()];
  .timer.addjob.custom[`mempoll; {.primary.pollmem[]}; (); 1; 2; ()!()];
  .timer.addjob.custom[`timeoutcheck; {.primary.checktimeouts[]}; (); 1; 2; ()!()];
  .primary.cgroupdir:.cgroup.dir[];
  .primary.oomkills:.cgroup.oomkills .primary.cgroupdir;
  .log.info "primary started, listening on ",string system "p";
  .primary.starttime:: .z.P;
 };

// start primary
.primary.start[];