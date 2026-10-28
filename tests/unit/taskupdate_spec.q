/ unit specs for .primary.taskupdate, the only way a task changes state
/ loads primary.q once (spawning off); each test puts its own task (id 900) in a known state first
/ run: tests/run.sh tests/unit/taskupdate_spec.q

setenv[`SPAWN_SECONDARY;enlist "0"];
if[not `primary in key `; system "l src/primary.q"];

.ut.tuid:900;

/ a full task row for .ut.tuid in state s
.ut.tuprow:{[s]
  `taskid`tasktype`args`priority`submittedtime`memestimate`timeout`retriesmax`retrycount`state`secondaryid`dispatchedtime`startedtime`finishedtime`membefore`memafter`err`reason`resultpath`resultbytes!
  (.ut.tuid;`noop;enlist 1;0i;.z.P;0N;00:01:00.000;3i;0i;s;0N;0Np;0Np;0Np;0N;0N;"";`; `; 0N)
 };

/ put task .ut.tuid into state s, replacing any earlier row
.ut.tuset:{[s]
  delete from `tasks where taskid=.ut.tuid;
  `tasks upsert .ut.tuprow s;
 };

.ut.tuget:{[] tasks .ut.tuid};

.tst.desc[".primary.taskupdate - legal moves"]{
  before{
    `.log.info mock {[x] ::};
    `.ut.warns set 0;
    `.log.warn mock {[x] .ut.warns+:1};
    };
  should["move queued to dispatched and record the secondary"]{
    .ut.tuset `queued;
    1b musteq .primary.taskupdate[.ut.tuid;`dispatched;enlist[`secondaryid]!enlist 2];
    r:.ut.tuget[];
    `dispatched musteq r`state;
    2 musteq r`secondaryid;
    1b musteq not null r`dispatchedtime;
    };
  should["move dispatched to running and stamp the start time"]{
    .ut.tuset `dispatched;
    1b musteq .primary.taskupdate[.ut.tuid;`running;()!()];
    r:.ut.tuget[];
    `running musteq r`state;
    1b musteq not null r`startedtime;
    };
  should["move running to done and store the result and memory"]{
    .ut.tuset `running;
    1b musteq .primary.taskupdate[.ut.tuid;`done;`membefore`memafter`resultpath`resultbytes!(1000;800;`:/tmp/x;16)];
    r:.ut.tuget[];
    `done musteq r`state;
    1b musteq not null r`finishedtime;
    `:/tmp/x musteq r`resultpath;
    16 musteq r`resultbytes;
    1000 musteq r`membefore;
    800 musteq r`memafter;
    };
  should["move running to failed and store the error"]{
    .ut.tuset `running;
    1b musteq .primary.taskupdate[.ut.tuid;`failed;`err`reason!("boom";`unknown)];
    r:.ut.tuget[];
    `failed musteq r`state;
    "boom" mustmatch r`err;
    `unknown musteq r`reason;
    1b musteq not null r`finishedtime;
    };
  should["allow dispatched to failed (secondary died before starting)"]{
    .ut.tuset `dispatched;
    1b musteq .primary.taskupdate[.ut.tuid;`failed;()!()];
    `failed musteq .ut.tuget[]`state;
    };
  should["show the move in the status task counts"]{
    .ut.tuset `queued;
    n:.primary.status[]`taskcounts;
    .primary.taskupdate[.ut.tuid;`dispatched;()!()];
    m:.primary.status[]`taskcounts;
    (n[`queued]-1i) musteq m`queued;
    (n[`dispatched]+1i) musteq m`dispatched;
    };
 };

.tst.desc[".primary.taskupdate - rejected moves leave the task alone"]{
  before{
    `.log.info mock {[x] ::};
    `.ut.warns set 0;
    `.log.warn mock {[x] .ut.warns+:1};
    };
  should["reject a late done for a task that already failed"]{
    .ut.tuset `failed;
    r0:.ut.tuget[];
    0b musteq .primary.taskupdate[.ut.tuid;`done;()!()];
    r0 mustmatch .ut.tuget[];
    1 musteq .ut.warns;
    };
  should["reject skipping a state (queued to done)"]{
    .ut.tuset `queued;
    r0:.ut.tuget[];
    0b musteq .primary.taskupdate[.ut.tuid;`done;()!()];
    r0 mustmatch .ut.tuget[];
    };
  should["treat done as final"]{
    .ut.tuset `done;
    r0:.ut.tuget[];
    0b musteq any .primary.taskupdate[.ut.tuid;;()!()] each `queued`dispatched`running`failed;
    r0 mustmatch .ut.tuget[];
    };
  should["reject an unknown task without creating it"]{
    delete from `tasks where taskid=.ut.tuid;
    0b musteq .primary.taskupdate[.ut.tuid;`dispatched;()!()];
    0 musteq count select from tasks where taskid=.ut.tuid;
    };
  should["not let info override the new state"]{
    .ut.tuset `queued;
    1b musteq .primary.taskupdate[.ut.tuid;`dispatched;`state`secondaryid!(`done;2)];
    `dispatched musteq .ut.tuget[]`state;
    };
 };
