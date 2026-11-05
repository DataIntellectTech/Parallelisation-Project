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


// dict of secondaries ids to their pids that the primary started
.primary.spawned:(`long$())!`int$();

// when a secondary starts add it to the secondaries table
// example run:
// .primary.register ([id:5; pid:4000i; host:`localhost])
.primary.register:{[info]
  `secondaries upsert ([id: info`id; handle: .z.w; pid: info`pid; host: info`host; status: `free;
    lastheartbeat: .z.P; consecutivefails: 0i; healthy: 1b; spawned: info[`id] in key .primary.spawned;
    starttime: .z.P; registeredtime: .z.P; tasktypes: (); currenttask: 0N; rssanon: 0N; vmrss: 0N; memtime: 0Np]);
  .log.info "secondary ", string[info`id], " registered at: ", string .z.P;
 };

// called by each secondary to let the primary know it is not idle
// called from the secondary like:
// neg[.secondary.handle](`.primary.heartbeatcheck; .secondary.rssanon[])
.primary.heartbeatcheck:{[mem]
  update lastheartbeat:.z.P, rssanon:mem, memtime:.z.P from `secondaries where handle=.z.w;
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
// example uage:
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
  .log.info "spawned secondary ",string[x]," ,pid ",string pid;
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


// if a secondary loses connection mark it as closed
.z.pc:{[h]
  secid: first exec id from secondaries where handle=h;
  if[null secid; :()];
  update status:`closed, handle:0Ni, currenttask: 0N from `secondaries where id=secid;
  .log.info "secondary ",string[secid]," has closed its connection to the primary";
 };

// quitting the primary kills any spawned secondaries
.z.exit:{ if[count .primary.spawned; .primary.stop[]]};


// start sequence
.primary.start:{
  if[.primary.spawnsecondaries; .primary.spawn each 1+til .primary.numsecondaries];
  .timer.addjob.custom[`stalecheck; {.primary.check[]}; (); 1; 2; ()!()];
  .log.info "primary started, listening on ",string system "p";
  .primary.starttime:: .z.P;
 };

// start primary
.primary.start[];