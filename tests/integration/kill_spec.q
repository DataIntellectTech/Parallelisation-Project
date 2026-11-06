system "l tests/helpers/it.q";
/ integration: the brief's secondary kill - terminate a secondary mid-task, verify the task is re-queued and finishes
/ run with: bash tests/integration.sh kill
/ needs lost in RETRY_REASONS and TASK_RETRIES_MAX of 1 or more (the defaults)

.kl.wait:{[f;secs] end:.z.p+`timespan$1e9*secs; while[(not f[]) and .z.p<end; system "sleep 0.2"]; f[]};
.kl.job:{[tt;a;p] .it.q ({.primary.newjob . x}; (tt;a;p))};
.kl.jobstate:{[j] .it.q ({first exec state from jobs where jobid=x}; j)};
.kl.tasks:{[j] .it.q ({0!select from tasks where jobid=x}; j)};
.kl.secs:{.it.q ({0!secondaries}; ::)};
/ the first secondary running a task, as a dict (id, pid, currenttask)
.kl.running:{.it.q ({first 0!select id, pid, currenttask from secondaries where status=`busy, not null currenttask,
  currenttask in exec taskid from tasks where state=`running}; ::)};

.tst.desc["secondary kill: a task on a killed secondary is re-queued and finishes"]{
  should["have every spawned secondary registered and free"]{
    1b musteq .it.ready[];
    `.kl.n set count .kl.secs[];
    1b musteq .kl.n>1;
    };
  should["kill a secondary while it runs a task"]{
    n2:2*.kl.n;
    `.kl.j set .kl.job[`sleep; n2#3; ()!()];
    1b musteq .kl.wait[{not null .kl.running[]`id}; 15];
    `.kl.victim set .kl.running[];
    system "kill -9 ",string .kl.victim`pid;
    / its connection closes: the primary marks it closed
    1b musteq .kl.wait[{`closed~first exec status from .kl.secs[] where id=.kl.victim`id}; 15];
    };
  should["retry its task on another secondary, and finish the job"]{
    1b musteq .kl.wait[{`done~.kl.jobstate .kl.j}; 60];
    t:first select from .kl.tasks[.kl.j] where taskid=.kl.victim`currenttask;
    `done musteq t`state;
    1i musteq t`retrycount;
    1b musteq not t[`secondaryid]=.kl.victim`id;
    };
  should["finish every other task without a retry"]{
    t:.kl.tasks .kl.j;
    1b musteq all `done=t`state;
    1i musteq sum t`retrycount;
    };
  };
