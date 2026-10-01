// this is the master process that monitors secondaries and assigns tasks
// start from top level dir with 
// q master.q

// load in schema
system"l schemas/masterTables.q";

// load in common code libs
// todo: change this in the future to load in the entire common code or all files with an each
// also look at resolving the dir name for a full file path use an env var in the config file
system"l src/common/log.q";

// create master log file
.log.component: `master;


.master.start:{
  .log.openFile "logs";
  .log.info "master started";
 };

// start up master process
.master.start[];