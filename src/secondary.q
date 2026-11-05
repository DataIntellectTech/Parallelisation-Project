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

// if the primary's connection closes kill the secondary
.z.pc:{[h]
  if[not h~.secondary.handle; :()];
  .log.error "lost the connection to the primary, exiting";
  exit 1;
 };

// start sequence
.secondary.start:{
  .secondary.handle:: .secondary.connect[];
  @[.secondary.handle; (`.primary.register; .secondary.info); {[error] .log.error "registering with the primary failed with error: ",error,". Will exit the process now"; exit 1}];
  .timer.addjob.custom[`heartbeat; {.secondary.heartbeat[]}; (); 1; 2; ()!()];
  .log.info "secondary ",string[.secondary.id]," started";
 };

.secondary.start[];