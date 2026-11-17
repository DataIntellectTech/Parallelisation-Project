system "l tests/helpers/it.q";
/ integration: the brief's timeout - a long task is stopped at its timeout
/ run with: bash tests/integration.sh timeout

.to.wait:{[f;secs] end:.z.p+`timespan$1e9*secs; while[(not f[]) and .z.p<end; system "sleep 0.2"]; f[]};
.to.task:{[tid] .it.q ({first 0!select from tasks where taskid=x}; tid)};
.to.secs:{.it.q ({0!secondaries}; ::)};
/ 1b if the process is still running
.to.alive:{[p] @[{system "kill -0 ",string[x]," 2>/dev/null"; 1b}; p; {[e] 0b}]};

.tst.desc["timeout: a task that runs past its timeout fails, and its secondary is killed"]{
  should["have every spawned secondary registered and free"]{
    1b musteq .it.ready[];
    };
  should["fail a 20 second task with a 2 second timeout, as timeout"]{
    `.to.tid set .it.q ({.primary.newtask x}; ([tasktype:`sleep; args:20; timeout:00:00:02.000]));
    1b musteq not null .to.tid;
    1b musteq .to.wait[{`failed~.to.task[.to.tid]`state}; 15];
    t:.to.task .to.tid;
    `timeout musteq t`reason;
    `.to.t set t;
    };
  should["fail it soon after the timeout, not when the task would have ended"]{
    took:.to.t[`finishedtime]-.to.t[`dispatchedtime]^.to.t`startedtime;
    1b musteq took>=0D00:00:02;
    / the timeout check runs every second
    1b musteq took<0D00:00:05;
    };
  should["not retry it"]{
    0i musteq .to.t`retrycount;
    };
  should["kill the secondary that was running it"]{
    s:first select from .to.secs[] where id=.to.t`secondaryid;
    1b musteq .to.wait[{[p;x] not .to.alive p}[s`pid]; 10];
    1b musteq (s`status) in `closed`free;
    };
  should["still run new work on the other secondaries"]{
    ids:.it.q ({{.primary.newtask `tasktype`args!(`sumtil;x)} each x}; 100 200);
    1b musteq .to.wait[{[ids;x] all `done=.it.q ({exec state from tasks where taskid in x}; ids)}[ids]; 30];
    };
  };