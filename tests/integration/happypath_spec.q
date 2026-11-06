system "l tests/helpers/it.q";
/ integration: the brief's happy path - N secondaries, M tasks, all succeed
/ run with: bash tests/integration.sh happypath

/ wait up to secs seconds for f[] to be true; returns f[]
.hp.wait:{[f;secs] end:.z.p+`timespan$1e9*secs; while[(not f[]) and .z.p<end; system "sleep 0.2"]; f[]};
/ submit a job on the primary, returns its id
.hp.job:{[tt;a;p] .it.q ({.primary.newjob . x}; (tt;a;p))};
.hp.jobstate:{[j] .it.q ({first exec state from jobs where jobid=x}; j)};
.hp.tasks:{[j] .it.q ({0!select from tasks where jobid=x}; j)};
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
  should["run every task of a job to done"]{
    `.hp.j set .hp.job[`sumtil; .hp.args; ()!()];
    1b musteq .hp.wait[{`done~.hp.jobstate .hp.j}; 60];
    t:.hp.tasks .hp.j;
    (count .hp.args) musteq count t;
    1b musteq all `done=t`state;
    0i musteq sum t`retrycount;
    };
  should["save every result to disk, the same as running the task here"]{
    paths:.it.q ({.primary.jobpaths x}; .hp.j);
    (count .hp.args) musteq count paths;
    (.secondary.approvedtasks[`sumtil] each .hp.args) mustmatch get each paths;
    };
  should["use every secondary, and never run more tasks at once than there are secondaries"]{
    t:.hp.tasks .hp.j;
    .hp.n musteq count distinct t`secondaryid;
    1b musteq .hp.mostatonce[t]<=.hp.n;
    };
  should["leave every secondary free with no task"]{
    s:.hp.secs[];
    1b musteq all `free=s`status;
    1b musteq all null s`currenttask;
    };
  };
