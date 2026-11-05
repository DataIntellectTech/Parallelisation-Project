// this is a secondary process: it runs tasks the primary sends it and reports back
// example run
// x src/secondary.q -id 1

// load in common code libs
// todo: change this in the future to load in the entire common code or all files with an each
// also look at resolving the dir name for a full file path use an env var in the config file
system"l src/common/log.q";
system"l src/common/timer.q";
system"l src/common/os.q";
system"l src/approvedtasks.q";
system"l src/common/mem.q";

// if hdb set load it in
if[count .secondary.hdb:getenv `HDB_DIR;
  system "l ",getenv `HDB_DIR;
 ];

// get the id from start cmd
.secondary.opts: .Q.opt .z.x;
.secondary.id: "J"$first .secondary.opts`id;
.secondary.info:([id: .secondary.id; pid: .z.i; host: .z.h]);

// used to connect and register with primary
.secondary.connect:{
  pri:`$"::",getenv `PRIMARY_PORT;
  .log.info "trying to open a handle to primary process on: ",string pri;
  sechandle:@[hopen;  pri; {.log.error "the secondary has failed to connect to the primary, failed with error: ",x,". Will exit the process now"; exit 1}];
  sechandle
 };

// this secondary's memory as the kernel counts it (RssAnon, bytes)
.secondary.rssanon:{first exec rssanon from .mem.read enlist .z.i};

// send hb and mem updates to primary
.secondary.heartbeat:{
  neg[.secondary.handle](`.primary.heartbeatcheck; .secondary.rssanon[]);
 };

// called by the primary to kill spawned secondaries
.secondary.stop:{
  .log.info "told to stop by the primary, exiting";
  exit 0;
 };

// send an async message to the primary and flush it straight away
// used mainly for updating the primary on tasks and memory 
.secondary.send:{[msg] neg[.secondary.handle] msg; neg[.secondary.handle][]};

// secondary tells primary it is starting, record mem before, run task, record mem after result, .Q.gc[], save result, returns where result is saved and its size
.secondary.runtask:{[tid; tasktype; args]
  .secondary.send (`.primary.taskupdate; tid; `running; ()!());
  membefore:.mem.readandclear[]`rssanon;
  if[not tasktype in at: key .secondary.approvedtasks;
    .log.warn "the task ",string[tasktype]," is not in the approved tasks list. Approved tasks are: ",", " sv string at;
    :.secondary.send (`.primary.taskupdate; tid; `failed; ([err: "unknown tasktype: ",string tasktype; reason: `error; membefore: membefore; memafter: membefore]))];
  res:@[{.secondary.approvedtasks[x] y}[tasktype;]; args; {[error] (`failure; error)}];
  memafter:first exec vmhwm from .mem.read enlist .z.i;
  if[`failure ~ first res;
    .Q.gc[];
    memaftergc:.secondary.rssanon[];
    .log.warn "task ",string[tid],", failed with error: ",last res;
    :.secondary.send (`.primary.taskupdate; tid; `failed; ([err: last res; reason: `error; membefore: membefore; memafter: memafter; memaftergc: memaftergc]))];
  saved:.secondary.save[tid; res];
  res:(::);
  .Q.gc[];
  memaftergc:.secondary.rssanon[];
  if[`failure ~ first saved;
    .log.warn "task ",string[tid],", could not save its result: ",last saved;
    :.secondary.send (`.primary.taskupdate; tid; `failed; ([err: "could not save the result: ",last saved; reason: `savefailed; membefore: membefore; memafter: memafter; memaftergc: memaftergc]))];
  .log.info "task ",string[tid]," is complete, result saved to ",string first saved;
  .secondary.send (`.primary.taskupdate; tid; `done; ([resultpath: first saved; resultbytes: last saved; membefore: membefore; memafter: memafter; memaftergc: memaftergc]));
 };

// save a tasks result, returns path and bytes, doesnt save if a null is the result
// this path will change when we add in jobs to
// $RESPATH/primary_session/jobID/each_taskID
.secondary.save:{[tid; res]
  if[(::)~res; :(`; 0)];
  path:hsym `$.secondary.resultsdir,"/",string tid;
  @[{[p;r] p set r; (p; hcount p)}[path]; res; {[e] (`failure; e)}]
 };


// if the primary's connection closes kill the secondary
.z.pc:{[h]
  if[not h~.secondary.handle; :()];
  .log.error "lost the connection to the primary, exiting";
  exit 1;
 };

// start sequence
.secondary.start:{
  .secondary.handle:: .secondary.connect[];
  .secondary.resultsdir:: @[.secondary.handle; (`.primary.register; .secondary.info); {[error] .log.error "registering with the primary failed with error: ",error,". Will exit the process now"; exit 1}];
  .log.info "registered with the primary, saving results in ",.secondary.resultsdir;
  .timer.addjob.custom[`heartbeat; {.secondary.heartbeat[]}; (); 1; 2; ()!()];
  .log.info "secondary ",string[.secondary.id]," started";
 };

.secondary.start[];