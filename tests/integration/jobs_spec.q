system "l tests/helpers/it.q";
/ integration: jobs - one task per arg, results load in task order, a failed part fails the job,
/ and a job is refused when its task type needs more than the cap
/ run with: bash tests/integration.sh jobs

.jb.wait:{[f;secs] end:.z.p+`timespan$1e9*secs; while[(not f[]) and .z.p<end; system "sleep 0.2"]; f[]};
.jb.job:{[tt;a;p] .it.q ({.primary.newjob . x}; (tt;a;p))};
.jb.state:{[j] .it.q ({first exec state from jobs where jobid=x}; j)};
.jb.row:{[j] .it.q ({first 0!select from jobs where jobid=x}; j)};
.jb.tasks:{[j] .it.q ({`taskid xasc 0!select from tasks where jobid=x}; j)};
.jb.mb:1048576;

/ the approved task functions, to work out the expected results here
system "l src/approvedtasks.q";

.tst.desc["jobs: one task per arg, results in task order, failures and refusals"]{
  should["have every spawned secondary registered and free"]{
    1b musteq .it.ready[];
    };
  should["run every task of a job to done"]{
    `.jb.args set 1000*1+til 10;
    `.jb.j set .jb.job[`sumtil; .jb.args; ()!()];
    1b musteq .jb.wait[{`done~.jb.state .jb.j}; 60];
    t:.jb.tasks .jb.j;
    (count .jb.args) musteq count t;
    1b musteq all `done=t`state;
    };
  should["record the job: its type, user, task count and the size of its results"]{
    r:.jb.row .jb.j;
    t:.jb.tasks .jb.j;
    `sumtil musteq r`tasktype;
    .z.u musteq r`user;
    (`int$count .jb.args) musteq r`ntasks;
    (sum t`resultbytes) musteq r`resultbytes;
    1b musteq all .z.u=t`user;
    };
  should["give the result paths in task order, under <run>/<jobid>/<taskid>"]{
    paths:.it.q ({.primary.jobpaths x}; .jb.j);
    (.secondary.approvedtasks[`sumtil] each .jb.args) mustmatch get each hsym paths;
    parts:"/" vs/: string paths;
    ((count paths)#enlist string .jb.j) mustmatch {x count[x]-2} each parts;
    (string (.jb.tasks .jb.j)`taskid) mustmatch last each parts;
    };
  should["save a task outside a job under <run>/nojob/<taskid>"]{
    tid:.it.q ({.primary.newtask x}; ([tasktype:`sumtil; args:10]));
    1b musteq .jb.wait[{[t;x] `done~.it.q ({tasks[x]`state}; t)}[tid]; 30];
    parts:"/" vs string .it.q ({tasks[x]`resultpath}; tid);
    ("nojob"; string tid) mustmatch -2#parts;
    };
  should["fail the job when a part fails, and cancel its queued parts"]{
    `.jb.f set .jb.job[`fail; til 6; ()!()];
    1b musteq .jb.wait[{`failed~.jb.state .jb.f}; 30];
    / parts that were already running finish (and fail too)
    1b musteq .jb.wait[{all `failed=(.jb.tasks .jb.f)`state}; 30];
    t:.jb.tasks .jb.f;
    1b musteq 0<sum `cancelled=t`reason;
    / a cancelled task was never sent to a secondary
    1b musteq all null exec dispatchedtime from t where reason=`cancelled;
    0i musteq sum t`retrycount;
    1b musteq 0<count (.jb.row .jb.f)`err;
    };
  should["learn a task type's memory, and give the next job's tasks that estimate"]{
    `.jb.h set .jb.job[`hold; enlist ([mb:200; secs:1]); ()!()];
    1b musteq .jb.wait[{`done~.jb.state .jb.h}; 30];
    j2:.jb.job[`hold; enlist ([mb:100; secs:1]); ()!()];
    / the estimate is what the 200MB task used: at least 190MB
    1b musteq all (190*.jb.mb)<=(.jb.tasks j2)`memestimate;
    1b musteq .jb.wait[{[j;x] `done~.jb.state j}[j2]; 30];
    };
  should["refuse a job whose task type has needed more than the cap"]{
    / lower the framework's cap below what hold tasks have used
    .it.q ({`.primary.memcap set x; `.primary.cgroupcap set x}; 100*.jb.mb);
    e:.it.q ({@[{.primary.newjob . x}; x; {x}]}; (`hold; enlist ([mb:10; secs:1]); ()!()));
    1b musteq e like "job refused*";
    };
  };