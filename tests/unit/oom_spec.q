/ unit specs for OOM labelling: .primary.oomkilled, and its use in .z.pc to fail a task as oom rather than lost
/ loads primary.q once (spawning off). .cgroup.oomkills is mocked to return .ut.omn (the kernel's oom_kill count),
/ .primary.spawn is mocked to record restarts, and .z.pc is called directly with the handle that closed
/ run: tests/run.sh tests/unit/oom_spec.q

setenv[`SPAWN_SECONDARY;enlist "0"];
if[not `primary in key `; system "l src/primary.q"];

/ empty the tables and register secondaries with ids ids (all free, all on handle 0i)
.ut.omreset:{[ids]
  delete from `secondaries;
  delete from `tasks;
  .primary.lasttaskid:0;
  {[i] .primary.register `id`pid`host`port!(i;100i+`int$i;`localhost;45000i+`int$i)} each ids;
 };

/ send a 10s sleep task to secondary sid and mark it running, returns its id
.ut.omrun:{[sid]
  tid:.primary.newtask `tasktype`args!(`sleep;10);
  .primary.sendtask[sid;tid];
  .primary.taskupdate[tid;`running;()!()];
  tid
 };

/ logs silenced, no memory cap, kernel count under test control (starts at 0, as does ours), restarts recorded
.ut.ommocks:{[]
  .tst.mock[`.log.info; {[x] ::}];
  .tst.mock[`.log.warn; {[x] ::}];
  .tst.mock[`.primary.tasktypes; `sumtil`sleep`fail];
  .tst.mock[`.primary.retryreasons; `lost`sendfailed];
  .tst.mock[`.primary.memcap; 0N];
  .tst.mock[`.primary.cgroupdir; "/sys/fs/cgroup/test.scope"];
  .tst.mock[`.primary.oomkills; 0];
  `.ut.omn set 0;
  .tst.mock[`.cgroup.oomkills; {[d] .ut.omn}];
  .tst.mock[`.primary.spawned; 1 2!101 102i];
  .tst.mock[`.primary.respawnmax; 3];
  .tst.mock[`.primary.respawns; (`long$())!`long$()];
  `.ut.omspawns set `long$();
  .tst.mock[`.primary.spawn; {[n] .ut.omspawns,:n}];
  .tst.mock[`.secondary.runtask; {[tid;tt;a] ::}];
 };

.tst.desc[".primary.oomkilled"]{
  before{
    .ut.ommocks[];
    };
  should["be false when the kernel count has not changed"]{
    0b musteq .primary.oomkilled[];
    0 musteq .primary.oomkills;
    };
  should["be true when the kernel count has risen, and count the kill"]{
    `.ut.omn set 1;
    1b musteq .primary.oomkilled[];
    1 musteq .primary.oomkills;
    };
  should["be false the second time for the same kill"]{
    `.ut.omn set 1;
    .primary.oomkilled[];
    0b musteq .primary.oomkilled[];
    1 musteq .primary.oomkills;
    };
  should["claim one kill per call when several happen at once"]{
    `.ut.omn set 2;
    110b mustmatch {[x] .primary.oomkilled[]} each til 3;
    2 musteq .primary.oomkills;
    };
  should["be false when the cgroup count cannot be read"]{
    `.ut.omn set 0N;
    0b musteq .primary.oomkilled[];
    0 musteq .primary.oomkills;
    };
 };

.tst.desc[".z.pc - a secondary killed for memory"]{
  before{
    .ut.ommocks[];
    .ut.omreset enlist 1;
    };
  should["fail its task with reason oom"]{
    tid:.ut.omrun 1;
    `.ut.omn set 1;
    .z.pc 0i;
    `failed musteq tasks[tid]`state;
    `oom musteq tasks[tid]`reason;
    1b musteq tasks[tid][`err] like "*too much memory*";
    };
  should["not retry the task"]{
    tid:.ut.omrun 1;
    `.ut.omn set 1;
    .z.pc 0i;
    0i musteq tasks[tid]`retrycount;
    };
  should["still restart the secondary"]{
    .ut.omrun 1;
    `.ut.omn set 1;
    .z.pc 0i;
    (enlist 1) mustmatch .ut.omspawns;
    `closed musteq secondaries[1]`status;
    };
  should["count the kill even when the secondary had no task"]{
    `.ut.omn set 1;
    mustnotthrow[(); {[] .z.pc 0i}];
    1 musteq .primary.oomkills;
    };
 };

.tst.desc[".z.pc - any other close"]{
  before{
    .ut.ommocks[];
    .ut.omreset enlist 1;
    };
  should["fail the task as lost and retry it when the kernel count has not changed"]{
    tid:.ut.omrun 1;
    .z.pc 0i;
    1i musteq tasks[tid]`retrycount;
    / the only secondary is now closed, so the retry waits in the queue
    `queued musteq tasks[tid]`state;
    0 musteq .primary.oomkills;
    };
  should["not use up a kill for a connection that is not a secondary"]{
    `.ut.omn set 1;
    .z.pc 77i;
    0 musteq .primary.oomkills;
    };
  should["fail the task as lost when there is no cgroup count"]{
    tid:.ut.omrun 1;
    `.ut.omn set 0N;
    .z.pc 0i;
    1i musteq tasks[tid]`retrycount;
    0 musteq .primary.oomkills;
    };
 };