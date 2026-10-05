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

// get env vars
.primary.stale:00:00:00.001*"J"$getenv`STALE_MS;
.primary.heartbeat:00:00:00.001*"J"$getenv`HEARTBEAT_MS;


// when a secondary starts add it to the secondaries table
// example run:
// .primary.register ([id:5; handle:0i; pid:4000i; host:`localhost; port:45001i ])
.primary.register:{[info]
  `secondaries upsert (info`id; .z.w; info`pid; info`host; info`port; `free; .z.P; 0N; 0Ni; 1b; 0b; .z.P; .z.P; (); 0N);
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
    update status:`stale from secondaries where id in stale;
    .log.warn "no heartbeat from secondary ",(", " sv string stale)];
 };


// ipc handlers that need editted

// if a connection is close we need to mark it as closed
.z.pc:{[h]
  secid: first exec id from secondaries where handle=h;
  if[null secid; :()];
  update status:`closed, handle:0Ni from `secondaries where id=secid;
  .log.info "secondary ",string[secid]," has closed its connection to the primary";
 };


// start sequence
.primary.start:{[]
  .timer.addjob.custom[`stalecheck; {.primary.check[]}; (); 1; 2; ()!()];
  .log.info "primary started, listening on ",string system "p";
  };

// start primary
.primary.start[];