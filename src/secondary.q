// this is a secondary process: it runs tasks the master sends it and reports back

// load in common code libs
// todo: change this in the future to load in the entire common code or all files with an each
// also look at resolving the dir name for a full file path use an env var in the config file
system"l src/common/log.q";

// get the id form start cmd
.secondary.opts:.Q.opt .z.x;
.secondary.id:"J"$first .secondary.opts`id;

// tag every log line with secondary:<id>, e.g. secondary:1
.log.component:`$"sec",string .secondary.id;

.secondary.start:{
  .log.openFile "logs";
  .log.info "secondary ",string[.secondary.id]," started, listening on ",string system "p";
 };

// start up secondary process
.secondary.start[];
