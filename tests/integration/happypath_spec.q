system "l tests/helpers/it.q";
/ integration: the brief's happy path - N secondaries, M tasks, all succeed
/ run with: bash tests/integration.sh happypath

/ wait up to secs seconds for f[] to be true; returns f[]
.hp.wait:{[f;secs] end:.z.p+`timespan$1e9*secs; while[(not f[]) and .z.p<end; system "sleep 0.2"]; f[]};
/ queue one task per arg on the primary, returns their ids
.hp.submit:{[tt;a] .it.q ({[x] {[tt;a] .primary.newtask `tasktype`args!(tt;a)}[x 0] each x 1}; (tt;a))};
.hp.tasks:{[ids] .it.q ({`taskid xasc 0!select from tasks where taskid in x}; ids)};
.hp.finished:{[ids] all (.hp.tasks ids)[`state] in `done`failed};
.hp.secs:{.it.q ({0!secondaries}; ::)};
/ the most tasks running at the same time, from their dispatched and finished times
.hp.mostatonce:{[t] s:t`dispatchedtime; f:t`finishedtime; max {[s;f;x] sum (s<=x) & x<f}[s;f] each s};

/ the approved task functions, to work out the expected results here
system "l src/approvedtasks.q";

.hp.args:1000*1+til 20;

.tst.desc["happy path: N secondaries, M tasks, all succeed"]{
  should["have every spawned secondary registered and free"]{
    1b musteq .it.ready[];
    `.hp.n set count .hp.secs[];
    1b musteq .hp.n>1;
    };
  should["run every task to done"]{
    `.hp.ids set .hp.submit[`sumtil; .hp.args];
    1b musteq not any null .hp.ids;
    1b musteq .hp.wait[{.hp.finished .hp.ids}; 60];
    t:.hp.tasks .hp.ids;
    (count .hp.args) musteq count t;
    1b musteq all `done=t`state;
    0i musteq sum t`retrycount;
    };
  should["save every result to disk, the same as running the task here"]{
    paths:(.hp.tasks .hp.ids)`resultpath;
    1b musteq not any null paths;
    (.secondary.approvedtasks[`sumtil] each .hp.args) mustmatch get each hsym paths;
    };
  should["use every secondary, and never run more tasks at once than there are secondaries"]{
    t:.hp.tasks .hp.ids;
    .hp.n musteq count distinct t`secondaryid;
    1b musteq .hp.mostatonce[t]<=.hp.n;
    };
  should["leave every secondary free with no task"]{
    s:.hp.secs[];
    1b musteq all `free=s`status;
    1b musteq all null s`currenttask;
    };
  };