system "l tests/helpers/it.q";
/ integration: the brief's timeout - a long task is stopped at its timeout
/ run with: bash tests/integration.sh timeout

.to.wait:{[f;secs] end:.z.p+`timespan$1e9*secs; while[(not f[]) and .z.p<end; system "sleep 0.2"]; f[]};
.to.job:{[tt;a;p] .it.q ({.primary.newjob . x}; (tt;a;p))};
.to.jobstate:{[j] .it.q ({first exec state from jobs where jobid=x}; j)};
.to.tasks:{[j] .it.q ({0!select from tasks where jobid=x}; j)};
.to.secs:{.it.q ({0!secondaries}; ::)};
/ 1b if the process is still running
.to.alive:{[p] @[{system "kill -0 ",string[x]," 2>/dev/null"; 1b}; p; {[e] 0b}]};

.tst.desc["timeout: a task that runs past its timeout fails, and its secondary is killed"]{
  should["have every spawned secondary registered and free"]{
    1b musteq .it.ready[];
    };
  should["fail a 20 second task with a 2 second timeout, as timeout"]{
    `.to.j set .to.job[`sleep; enlist 20; ([timeout:00:00:02.000])];
    1b musteq .to.wait[{`failed~.to.jobstate .to.j}; 15];
    t:first .to.tasks .to.j;
    `failed musteq t`state;
    `timeout musteq t`reason;
    `.to.task set t;
    };
  should["fail it soon after the timeout, not when the task would have ended"]{
    took:.to.task[`finishedtime]-.to.task[`dispatchedtime]^.to.task`startedtime;
    1b musteq took>=0D00:00:02;
    / the timeout check runs every second
    1b musteq took<0D00:00:05;
    };
  should["not retry it"]{
    0i musteq .to.task`retrycount;
    };
  should["kill the secondary that was running it"]{
    sid:.to.task`secondaryid;
    s:first select from .to.secs[] where id=sid;
    1b musteq .to.wait[{[p;x] not .to.alive p}[s`pid]; 10];
    1b musteq (s`status) in `closed`free;
    };
  should["still run new work on the other secondaries"]{
    j2:.to.job[`sumtil; 100 200; ()!()];
    1b musteq .to.wait[{[j;x] `done~.to.jobstate j}[j2]; 30];
    };
  };
