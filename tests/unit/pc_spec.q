/ unit specs for .z.pc on the primary: a closed secondary is marked closed and its in-flight task is failed
/ loads primary.q once (spawning off). Secondaries are added with .primary.register, which stores .z.w (0i locally),
/ tasks are given to them with .primary.sendtask (the send on 0i runs locally, .secondary.runtask is mocked),
/ and the tests call .z.pc directly with the handle that closed
/ run: tests/run.sh tests/unit/pc_spec.q

setenv[`SPAWN_SECONDARY;enlist "0"];
if[not `primary in key `; system "l src/primary.q"];

/ empty both tables, then register secondaries with ids ids (all free, all on handle 0i)
.ut.pcreset:{[ids]
  delete from `secondaries;
  delete from `tasks;
  .primary.lasttaskid:0;
  {[i] .primary.register `id`pid`host`port!(i;100i+`int$i;`localhost;45000i+`int$i)} each ids;
 };

/ add a task and send it to secondary sid, returns the task id
.ut.pcsend:{[sid]
  tid:.primary.newtask `tasktype`args!(`sleep;10);
  .primary.sendtask[sid;tid];
  tid
 };

/ quiet logs (counting warnings), a fixed task type list, and a runtask that does nothing
/ uses .tst.mock[name;value]: the infix "mock" only exists inside .tst.desc
.ut.pcmocks:{[]
  .tst.mock[`.log.info; {[x] ::}];
  `.ut.pcwarns set 0;
  .tst.mock[`.log.warn; {[x] .ut.pcwarns+:1}];
  .tst.mock[`.primary.tasktypes; `sumtil`sleep`fail];
  .tst.mock[`.secondary.runtask; {[tid;tt;a] ::}];
 };

.tst.desc[".z.pc - a secondary with a task"]{
  before{
    .ut.pcmocks[];
    .ut.pcreset enlist 1;
    };
  should["fail a dispatched task with reason lost"]{
    tid:.ut.pcsend 1;
    `dispatched musteq tasks[tid]`state;
    .z.pc 0i;
    r:tasks tid;
    `failed musteq r`state;
    `lost musteq r`reason;
    "secondary lost" mustmatch r`err;
    1b musteq not null r`finishedtime;
    };
  should["fail a running task with reason lost"]{
    tid:.ut.pcsend 1;
    .primary.taskupdate[tid;`running;()!()];
    .z.pc 0i;
    `failed musteq tasks[tid]`state;
    `lost musteq tasks[tid]`reason;
    };
  should["mark the secondary closed with no handle and no current task"]{
    .ut.pcsend 1;
    .z.pc 0i;
    `closed musteq secondaries[1]`status;
    1b musteq null secondaries[1]`handle;
    1b musteq null secondaries[1]`currenttask;
    };
  should["log one warning for the lost task"]{
    .ut.pcsend 1;
    .z.pc 0i;
    1 musteq .ut.pcwarns;
    };
  should["not give the closed secondary another task"]{
    .ut.pcsend 1;
    .z.pc 0i;
    tid:.primary.newtask `tasktype`args!(`sleep;1);
    .primary.dispatch[];
    `queued musteq tasks[tid]`state;
    };
 };

.tst.desc[".z.pc - leaves everything else alone"]{
  before{
    .ut.pcmocks[];
    .ut.pcreset 1 2;
    };
  should["not touch another secondary or its task"]{
    t1:.ut.pcsend 1;
    t2:.ut.pcsend 2;
    / give secondary 2 its own handle so only secondary 1 is on 0i
    update handle:5i from `secondaries where id=2;
    .z.pc 0i;
    `failed musteq tasks[t1]`state;
    `dispatched musteq tasks[t2]`state;
    `busy musteq secondaries[2]`status;
    t2 musteq secondaries[2]`currenttask;
    };
  should["not touch queued tasks"]{
    .ut.pcsend 1;
    update handle:5i from `secondaries where id=2;
    qt:.primary.newtask `tasktype`args!(`sleep;1);
    .z.pc 0i;
    `queued musteq tasks[qt]`state;
    };
  should["change no task when a free secondary closes"]{
    update handle:5i from `secondaries where id=2;
    qt:.primary.newtask `tasktype`args!(`sleep;1);
    t0:tasks;
    .z.pc 0i;
    `closed musteq secondaries[1]`status;
    t0 mustmatch tasks;
    0 musteq .ut.pcwarns;
    };
  should["leave a task that already finished as done"]{
    update handle:5i from `secondaries where id=2;
    tid:.ut.pcsend 1;
    .primary.taskupdate[tid;`running;()!()];
    .primary.taskupdate[tid;`done;`result`membefore`memafter!(enlist 1;0;0)];
    .z.pc 0i;
    `done musteq tasks[tid]`state;
    `closed musteq secondaries[1]`status;
    };
  should["do nothing for a handle that is not a secondary"]{
    tid:.ut.pcsend 1;
    s0:secondaries;
    t0:tasks;
    .z.pc 77i;
    s0 mustmatch secondaries;
    t0 mustmatch tasks;
    };
 };