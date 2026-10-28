/ unit specs for .primary.getresult: loading a finished task's result from disk
/ loads primary.q once (spawning off). A result is saved by hand in a temporary folder; no secondaries are
/ registered, so newtask only queues
/ run: tests/run.sh tests/unit/results_spec.q

setenv[`SPAWN_SECONDARY;enlist "0"];
if[not `primary in key `; system "l src/primary.q"];

.ut.rddir:"/tmp/qfw-results-spec";

/ an empty test folder and tasks table, then two tasks: .ut.rddone (done, result 45 saved as file 1) and .ut.rdqueued
.ut.rdreset:{[]
  system "rm -rf ",.ut.rddir;
  system "mkdir -p ",.ut.rddir;
  delete from `tasks;
  .primary.lasttaskid:0;
  `.ut.rddone set .primary.newtask `tasktype`args!(`sumtil;10);
  `.ut.rdqueued set .primary.newtask `tasktype`args!(`sumtil;10);
  p:hsym `$.ut.rddir,"/",string .ut.rddone;
  p set 45;
  update state:`done, resultpath:p, resultbytes:hcount p from `tasks where taskid=.ut.rddone;
 };

.tst.desc[".primary.getresult"]{
  before{
    `.log.info mock {[x] ::};
    `.log.warn mock {[x] ::};
    `.primary.tasktypes mock `sumtil`sleep`fail;
    `.primary.memcap mock 0N;
    .ut.rdreset[];
    };
  after{
    system "rm -rf ",.ut.rddir;
    };
  should["load a finished task's result"]{
    45 musteq .primary.getresult .ut.rddone;
    };
  should["error for a task that isn't done"]{
    mustthrow[(); {[] .primary.getresult .ut.rdqueued}];
    };
  should["error for a task that doesn't exist"]{
    mustthrow[(); {[] .primary.getresult 99}];
    };
  should["error for a done task with no result"]{
    update resultpath:`, resultbytes:0N from `tasks where taskid=.ut.rddone;
    mustthrow[(); {[] .primary.getresult .ut.rddone}];
    };
  should["error when the result file has gone"]{
    system "rm -f ",.ut.rddir,"/*";
    mustthrow[(); {[] .primary.getresult .ut.rddone}];
    };
 };

