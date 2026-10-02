// this is a secondary process: it runs tasks the master sends it and reports back
// example run
// x src/secondary.q  -p 45001 -id 1

// load in common code libs
// todo: change this in the future to load in the entire common code or all files with an each
// also look at resolving the dir name for a full file path use an env var in the config file
system"l src/common/log.q";

// get the id form start cmd
.secondary.opts:.Q.opt .z.x;
.secondary.id:"J"$first .secondary.opts`id;

.secondary.start:{
  .log.info "secondary ",string[.secondary.id]," started, listening on ",string system "p";
 };

// start up secondary process
.secondary.start[];