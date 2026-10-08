// this is a secondary process: it runs tasks the master sends it and reports back
// example run
// x src/secondary.q  -p 45001 -id 1

// load in common code libs
// todo: change this in the future to load in the entire common code or all files with an each
// also look at resolving the dir name for a full file path use an env var in the config file
system"l src/common/log.q";
system"l src/common/timer.q";
system"l src/common/os.q";


// get the id form start cmd
.secondary.opts: .Q.opt .z.x;
.secondary.id: "J"$first .secondary.opts`id;
.secondary.info:([id: .secondary.id; pid: .z.i; host: .z.h; port: system"p"]);

// used to connect and register with primary
.secondary.connect:{
  pri:`$"::",getenv `PRIMARY_PORT;
  .log.info "trying to open a handle to primary process on: ",string pri;
  sechandle:@[hopen;  pri; {.log.error "the secondary has failed to connect to the primary, failed with error: ",x,". Will exit the process now"; exit 0}];
  sechandle
 };

// send hb and mem updates to primary
.secondary.heartbeat:{
  neg[.secondary.handle](`.primary.heartbeatcheck; .Q.w[]`used);
 };

// called by the primary to kill spawned secondaries
.secondary.stop:{
  .log.info "told to stop by the primary, exiting";
  exit 0;
 };

// if the primary's connection closes there's nothing to work for, so exit
.z.pc:{[h]
  if[not h~.secondary.handle; :()];
  .log.error "lost the connection to the primary, exiting";
  exit 1;
 };

// we will set any secondarys oom_score to 1000 so it will be shut down first if the OS is out of memory
.secondary.oomscore:{
  oomscorepath:"/proc/",string[.z.i],"/oom_score_adj";
  system "sh -c 'echo 1000 > ",oomscorepath,"'";
  score:system"cat ",oomscorepath;
  $[score~"1000"; .log.info "oom_score_adj set to 1000"; .log.warn "could not set oom_score_adj, it is ",score];
 };

// start sequence
.secondary.start:{
  .secondary.oomscore[];
  .secondary.handle:: .secondary.connect[];
  neg[.secondary.handle](`.primary.register; .secondary.info);
  .timer.addjob.custom[`heartbeat; {.secondary.heartbeat[]}; (); 1; 2; ()!()];
  .log.info "secondary ",string[.secondary.id]," started, listening on ",string system "p";
 };

.secondary.start[];