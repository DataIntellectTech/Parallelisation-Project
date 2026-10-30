/ unit specs for task timeouts: .primary.checktimeouts and .primary.timeout
/ loads primary.q once (spawning off). Secondaries are registered on handle 0i (sends run locally, .secondary.runtask
/ is mocked), .os.kill9 is mocked to record the pids it would kill, and task times are backdated to make tasks late
/ run: tests/run.sh tests/unit/timeout_spec.q

setenv[`SPAWN_SECONDARY;enlist "0"];
if[not `primary in key `; system "l src/primary.q"];

/ empty the tables and register secondaries with ids ids (all free, all on handle 0i, pid 100+id)
.ut.toreset:{[ids]
  delete from `secondaries;
  delete from `tasks;
  .primary.lasttaskid:0;
  {[i] .primary.register `id`pid`host`port!(i;100i+`int$i;`localhost;45000i+`int$i)} each ids;
 };

/ send a 10s sleep task with a 1s timeout to secondary sid, optionally mark it running, returns its id
.ut.tosend:{[sid;run]
  tid:.primary.newtask `tasktype`args`timeout!(`sleep;10;00:00:01.000);
  .primary.sendtask[sid;tid];
  if[run; .primary.taskupdate[tid;`running;()!()]];
  tid
 };

/ make a task look like it started (and was dispatched) secs seconds ago
.ut.tolate:{[tid;secs] update dispatchedtime:.z.P-secs*0D00:00:01, startedtime:?[null startedtime;startedtime;.z.P-secs*0D00:00:01] from `tasks where taskid=tid};

/ logs counted, retries as in config, sends and kills recorded
.ut.tomocks:{[]
  .tst.mock[`.log.info; {[x] ::}];
  `.ut.towarns set 0;
  .tst.mock[`.log.warn; {[x] .ut.towarns+:1}];
  .tst.mock[`.primary.tasktypes; `sumtil`sleep`fail];
  .tst.mock[`.primary.retryreasons; `lost`sendfailed];
  .tst.mock[`.primary.memcap; 0N];
  .tst.mock[`.secondary.runtask; {[tid;tt;a] ::}];
  `.ut.tokills set `int$();
  .tst.mock[`.os.kill9; {[p] .ut.tokills,:p}];
 };

.tst.desc[".primary.checktimeouts - late tasks"]{
  before{
    .ut.tomocks[];
    .ut.toreset enlist 1;
    };
  should["fail a running task that is past its timeout, with reason timeout"]{
    tid:.ut.tosend[1;1b];
    .ut.tolate[tid;2];
    .primary.checktimeouts[];
    r:tasks tid;
    `failed musteq r`state;
    `timeout musteq r`reason;
    1b musteq r[`err] like "timed out*";
    };
  should["kill the secondary's process"]{
    tid:.ut.tosend[1;1b];
    .ut.tolate[tid;2];
    .primary.checktimeouts[];
    (enlist 101i) mustmatch .ut.tokills;
    };
  should["take the secondary out of use with no current task"]{
    tid:.ut.tosend[1;1b];
    .ut.tolate[tid;2];
    .primary.checktimeouts[];
    `closed musteq secondaries[1]`status;
    1b musteq null secondaries[1]`currenttask;
    };
  should["time out a dispatched task whose secondary never reported running"]{
    tid:.ut.tosend[1;0b];
    .ut.tolate[tid;2];
    .primary.checktimeouts[];
    `failed musteq tasks[tid]`state;
    `timeout musteq tasks[tid]`reason;
    };
  should["not retry a task that timed out"]{
    tid:.ut.tosend[1;1b];
    .ut.tolate[tid;2];
    .primary.checktimeouts[];
    0i musteq tasks[tid]`retrycount;
    `failed musteq tasks[tid]`state;
    };
  should["not give the killed secondary another task"]{
    tid:.ut.tosend[1;1b];
    q:.primary.newtask `tasktype`args!(`sleep;1);
    .ut.tolate[tid;2];
    .primary.checktimeouts[];
    `queued musteq tasks[q]`state;
    };
  should["log one warning per timeout"]{
    tid:.ut.tosend[1;1b];
    .ut.tolate[tid;2];
    .primary.checktimeouts[];
    1 musteq .ut.towarns;
    };
  should["log, not throw, when the kill fails"]{
    `.os.kill9 mock {[p] '"no such process"};
    tid:.ut.tosend[1;1b];
    .ut.tolate[tid;2];
    .primary.checktimeouts[];
    `failed musteq tasks[tid]`state;
    2 musteq .ut.towarns;
    };
 };

.tst.desc[".primary.checktimeouts - everything else is left alone"]{
  before{
    .ut.tomocks[];
    .ut.toreset 1 2;
    };
  should["leave a task that is still within its timeout"]{
    tid:.ut.tosend[1;1b];
    .primary.checktimeouts[];
    `running musteq tasks[tid]`state;
    0 musteq count .ut.tokills;
    };
  should["leave queued and done tasks alone however old"]{
    / finish d first: its done would dispatch any task already queued
    d:.ut.tosend[1;1b];
    .primary.taskupdate[d;`done;`resultpath`resultbytes`membefore`memafter!(`:x;0;0;0)];
    qt:.primary.newtask `tasktype`args`timeout!(`sleep;1;00:00:01.000);
    update submittedtime:.z.P-0D01:00, dispatchedtime:.z.P-0D01:00, startedtime:.z.P-0D01:00 from `tasks;
    .primary.checktimeouts[];
    0 musteq count .ut.tokills;
    `done`queued mustmatch tasks[([] taskid:d,qt)]`state;
    };
  should["time out every late task in one check"]{
    t1:.ut.tosend[1;1b];
    t2:.ut.tosend[2;1b];
    .ut.tolate[t1;2];
    .ut.tolate[t2;2];
    .primary.checktimeouts[];
    `failed`failed mustmatch tasks[([] taskid:t1,t2)]`state;
    (asc 101 102i) mustmatch asc .ut.tokills;
    };
  should["only time out the late task when one is late and one is not"]{
    t1:.ut.tosend[1;1b];
    t2:.ut.tosend[2;1b];
    .ut.tolate[t1;2];
    .primary.checktimeouts[];
    `failed`running mustmatch tasks[([] taskid:t1,t2)]`state;
    `busy musteq secondaries[2]`status;
    };
 };