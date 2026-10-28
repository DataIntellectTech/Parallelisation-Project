/ end to end: a real secondary runs tasks it is sent and reports back to the primary
/ dispatch isn't built yet, so .it.dispatch does on the primary by hand what .primary.dispatch will do:
/ create the task, mark the secondary busy, move the task to dispatched, send it .secondary.runtask
/ run: bash tests/integration.sh runtask
system "l tests/helpers/it.q";

/ create a task of type tt with args a and send it to secondary sid as type st (st is normally tt;
/ a different st tests the secondary's own whitelist). Runs on the primary over IPC, returns the task id
.it.dispatch:{[sid;tt;st;a]
  .it.q ({[sid;tt;st;a]
    tid:.primary.newtask `tasktype`args!(tt;a);
    update status:`busy, currenttask:tid from `secondaries where id=sid;
    .primary.taskupdate[tid;`dispatched;enlist[`secondaryid]!enlist sid];
    h:first exec handle from secondaries where id=sid;
    neg[h](`.secondary.runtask; tid; st; first tasks[tid]`args);
    tid}; sid; tt; st; a)
 };

/ a task's row from the primary, its state, and waiting for it to reach a state
.it.task:{[tid] .it.q ({[t] tasks t}; tid)};
.it.taskstate:{[tid] .it.task[tid]`state};
.it.waitstate:{[tid;s;secs] .it.waitfor[{[t;s;x] s~.it.taskstate t}[tid;s]; secs]};

.tst.desc["end to end: a secondary runs the tasks it is sent"]{
  should["have every spawned secondary registered and free"]{
    1b musteq .it.ready[];
    };
  should["run a sumtil task and send back its result"]{
    tid:.it.dispatch[1;`sumtil;`sumtil;1000000];
    1b musteq .it.waitstate[tid;`done;10];
    t:.it.task tid;
    499999500000 musteq get t`resultpath;
    1 musteq t`secondaryid;
    1b musteq all not null t`dispatchedtime`startedtime`finishedtime;
    };
  should["free the secondary once its task is done"]{
    1b musteq .it.waitfor[{`free~.it.status 1};5];
    1b musteq null first exec currenttask from .it.sec[] where id=1;
    };
  should["record a higher peak than the starting heap for a big task"]{
    tid:.it.dispatch[2;`sumtil;`sumtil;50000000];
    1b musteq .it.waitstate[tid;`done;20];
    t:.it.task tid;
    1b musteq t[`memafter]>t`membefore;
    };
  should["keep the secondary busy while the task runs"]{
    tid:.it.dispatch[1;`sleep;`sleep;2];
    1b musteq .it.waitstate[tid;`running;5];
    `busy musteq .it.status 1;
    1b musteq .it.waitstate[tid;`done;10];
    1b musteq .it.waitfor[{`free~.it.status 1};5];
    };
  should["report a task that throws as failed, with its error"]{
    tid:.it.dispatch[1;`fail;`fail;::];
    1b musteq .it.waitstate[tid;`failed;10];
    t:.it.task tid;
    "fail" mustmatch t`err;
    `error musteq t`reason;
    1b musteq .it.waitfor[{`free~.it.status 1};5];
    };
  should["refuse a task type the secondary has not approved, without running it"]{
    tid:.it.dispatch[2;`sumtil;`rm;"-rf /"];
    1b musteq .it.waitstate[tid;`failed;10];
    "unknown tasktype: rm" mustmatch .it.task[tid]`err;
    1b musteq .it.waitfor[{`free~.it.status 2};5];
    };
  should["record the task's real peak memory, not q's rounded heap"]{
    tid:.it.dispatch[1;`hold;`hold;`mb`secs!(300;1)];
    1b musteq .it.waitstate[tid;`done;10];
    t:.it.task tid;
    / a 300MB task: peak about 300MB plus q itself (~7MB); the old heap figure would have been 512MB
    1b musteq (t[`memafter]%1048576) within 300 340;
    1b musteq t[`membefore]<50*1048576;
   };
 };