/ unit specs for .primary.resultpath: where a finished task's result is saved
/ loads primary.q once (spawning off). A result is saved by hand in a temporary folder; no secondaries are
/ registered, so newtask only queues
/ run: tests/run.sh tests/unit/results_spec.q

setenv[`SPAWN_SECONDARY;enlist "0"];
if[not `primary in key `; system "l src/primary.q"];

.ut.rddir:"/tmp/qfw-results-spec";

/ an empty test folder and fresh tables, then two tasks: .ut.rddone (done, result 45 saved as a file) and .ut.rdqueued
.ut.rdreset:{[]
  system "rm -rf ",.ut.rddir;
  system "mkdir -p ",.ut.rddir;
  system "l schemas/primarytables.q";
  .primary.lasttaskid:0;
  `.ut.rddone set .primary.newtask `tasktype`args!(`sumtil;10);
  `.ut.rdqueued set .primary.newtask `tasktype`args!(`sumtil;10);
  p:hsym `$.ut.rddir,"/",string .ut.rddone;
  p set 45;
  update state:`done, resultpath:p, resultbytes:hcount p from `tasks where taskid=.ut.rddone;
 };

.tst.desc[".primary.resultpath"]{
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
  should["give the path of a finished task's result"]{
    (hsym `$.ut.rddir,"/",string .ut.rddone) musteq .primary.resultpath .ut.rddone;
    45 musteq get .primary.resultpath .ut.rddone;
    };
  should["error for a task that isn't done"]{
    mustthrow[(); {[] .primary.resultpath .ut.rdqueued}];
    };
  should["error for a task that doesn't exist"]{
    mustthrow[(); {[] .primary.resultpath 99}];
    };
  should["error for a done task with no result"]{
    update resultpath:`, resultbytes:0N from `tasks where taskid=.ut.rddone;
    mustthrow[(); {[] .primary.resultpath .ut.rddone}];
    };
  should["give the path even when the file has gone, so get is what errors"]{
    system "rm -f ",.ut.rddir,"/*";
    mustnotthrow[(); {[] .primary.resultpath .ut.rddone}];
    mustthrow[(); {[] get .primary.resultpath .ut.rddone}];
    };
 };