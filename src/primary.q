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


// dict of secondaries ids to their pids that the primary started
.primary.spawned:(`long$())!`int$();


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



// the one OS call di.os doesn't cover: start q in the background and get its pid
// a wrapper so unit specs can mock it (system can't be mocked)
// .primary.run:{[cmd] system cmd}; use in unit testing
.primary.send:{[h;msg] neg[h] msg; neg[h][]};

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
  {[h] @[.primary.send[h;];(`.secondary.stop;::);{[e] ::}]} each handles;   /// no stop sec func on sec.q script
  .os.sleep .primary.stopgraceperiod;
  left:p where .os.exists each "/proc/",/:string p:value .primary.spawned;
  if[count left;
    .log.warn "killing secondaries that didn't exit: pids ",", " sv string left;
    {[p] @[.os.kill9;p;{[e] ::}]} each left];
  .primary.spawned:(`long$())!`int$();
  .log.info "stopped";
 };



// ipc handlers that need editted

// if a connection is close we need to mark it as closed
.z.pc:{[h]
  secid: first exec id from secondaries where handle=h;
  if[null secid; :()];
  update status:`closed, handle:0Ni from `secondaries where id=secid;
  .log.info "secondary ",string[secid]," has closed its connection to the primary";
 };

// quitting the primary kills any spawned secondaries
.z.exit:{if[count .primary.spawned; .primary.stop[]]};

// start sequence
.primary.start:{[]
  if[.primary.spawnsecondaries; .primary.spawn each 1+til .primary.numsecondaries];
  .timer.addjob.custom[`stalecheck; {.primary.check[]}; (); 1; 2; ()!()];
  .log.info "primary started, listening on ",string system "p";
  };

// start primary
.primary.start[];