system "l tests/helpers/it.q";
/ integration: the brief's GC verification - .Q.gc[] runs after each task and the after-gc memory is recorded
/ run with: bash tests/integration.sh gc

.gc.wait:{[f;secs] end:.z.p+`timespan$1e9*secs; while[(not f[]) and .z.p<end; system "sleep 0.2"]; f[]};
.gc.job:{[tt;a;p] .it.q ({.primary.newjob . x}; (tt;a;p))};
.gc.jobstate:{[j] .it.q ({first exec state from jobs where jobid=x}; j)};
.gc.tasks:{[j] .it.q ({0!select from tasks where jobid=x}; j)};
.gc.secs:{.it.q ({0!secondaries}; ::)};
.gc.mb:1048576;

.tst.desc["gc: every task's memory is given back, and the after-gc figure is recorded"]{
  should["have every spawned secondary registered and free"]{
    1b musteq .it.ready[];
    `.gc.n set count .gc.secs[];
    };
  should["run a 300MB task on every secondary"]{
    `.gc.j set .gc.job[`hold; ([] mb:.gc.n#300; secs:.gc.n#1); ()!()];
    1b musteq .gc.wait[{`done~.gc.jobstate .gc.j}; 60];
    `.gc.t set .gc.tasks .gc.j;
    1b musteq all `done=.gc.t`state;
    };
  should["record memory before, at the peak and after the gc for every task"]{
    1b musteq all not null .gc.t`membefore;
    1b musteq all not null .gc.t`memafter;
    1b musteq all not null .gc.t`memaftergc;
    };
  should["see each task's 300MB at its peak"]{
    1b musteq all .gc.t[`memafter]>=290*.gc.mb;
    };
  should["see the 300MB given back after the gc: within 50MB of where each task started"]{
    1b musteq all .gc.t[`memaftergc]<.gc.t[`membefore]+50*.gc.mb;
    1b musteq all (.gc.t[`memafter]-.gc.t`memaftergc)>=250*.gc.mb;
    };
  should["show each secondary back at its small after-gc memory"]{
    s:.gc.secs[];
    1b musteq all s[`rssanon]<50*.gc.mb;
    };
  };
