// this is a secondary process: it runs tasks the master sends it and reports back
// example run
// x src/secondary.q  -p 45001 -id 1

// load in common code libs
// todo: change this in the future to load in the entire common code or all files with an each
// also look at resolving the dir name for a full file path use an env var in the config file
system"l src/common/log.q";
system"l src/common/timer.q";

// get the id form start cmd
.secondary.opts: .Q.opt .z.x;
.secondary.id: "J"$first .secondary.opts`id;
.secondary.info:([id: .secondary.id; pid: .z.i; host: .z.h; port: system"p"]);

// used to ocnnect and register with primary
.secondary.connect:{
  pri:`$"::",getenv `PRIMARY_PORT;
  .log.info "trying to open a handle to primary process on: ",string pri;
  sech:@[hopen;  pri; {.log.error "the secondary has failed to connect to the primary, failed with error: ",x,". Will exit the process now"; exit 0}];
  sech
 };

// send hb and mem updates to primary
.secondary.heartbeat:{
  neg[.secondary.handle](`.primary.heartbeatcheck; .Q.w[]`used);
 };

// start sequence
.secondary.start:{
  .secondary.handle:: .secondary.connect[];
  neg[.secondary.handle](`.primary.register; .secondary.info);
  .timer.addjob.custom[`heartbeat; {.secondary.heartbeat[]}; (); 1; 2; ()!()];
  .log.info "secondary ",string[.secondary.id]," started, listening on ",string system "p";
 };

.secondary.start[];