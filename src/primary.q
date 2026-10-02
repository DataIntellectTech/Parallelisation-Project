// this is the primary process that monitors secondaries and assigns tasks
// start from top level dir with 
// q src/primary.q -p 45000

// load in schema
system"l schemas/primaryTables.q";

// load in common code libs
// todo: change this in the future to load in the entire common code or all files with an each
// also look at resolving the dir name for a full file path use an env var in the config file
system"l src/common/log.q";

.primary.start:{[]
  .log.info "primary started, listening on ",string system "p";
  };

// start primary
.primary.start[];