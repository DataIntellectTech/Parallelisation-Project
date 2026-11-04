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

// start sequence
.primary.start:{
  .timer.addjob.custom[`stalecheck; {.primary.check[]}; (); 5; 2; ()!()];
  .log.info "primary started, listening on ",string system "p";
  .primary.starttime:: .z.P;
 };

// start primary
.primary.start[];