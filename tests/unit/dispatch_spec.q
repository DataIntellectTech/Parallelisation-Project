/ unit specs for .primary.dispatch and .primary.sendtask
/ loads primary.q once (spawning off). Secondaries are added with .primary.register, which stores .z.w,
/ and .z.w is 0i when called locally. A send on handle 0i (neg 0i is 0i) runs the message here,
/ so .secondary.runtask is mocked to record what would have been sent. A bad handle makes the send fail
/ run: tests/run.sh tests/unit/dispatch_spec.q

setenv[`SPAWN_SECONDARY;enlist "0"];
if[not `primary in key `; system "l src/primary.q"];

/ empty both tables, then register secondaries with ids ids (all free, all on handle 0i)
.ut.dpreset:{[ids]
  delete from `secondaries;
  delete from `tasks;
  .primary.lasttaskid:0;
  {[i] .primary.register `id`pid`host`port!(i;100i+`int$i;`localhost;45000i+`int$i)} each ids;
 };

/ add a queued task with priority p, returns its id
.ut.dptask:{[p] .primary.newtask `tasktype`args`priority!(`sumtil;100;p)};

/ the mocks shared by every test: quiet logs, a fixed task type list, and a runtask that records its calls
/ the mocks shared by every test: quiet logs, a fixed task type list, a runtask that records its calls, and no retries
/ uses .tst.mock[name;value] with brackets: the infix "mock" only exists while qspec runs a spec,
/ so it can't be used in a helper defined out here at load time
.ut.dpmocks:{[]
  .tst.mock[`.log.info; {[x] ::}];
  `.ut.dpwarns set 0;
  .tst.mock[`.log.warn; {[x] .ut.dpwarns+:1}];
  .tst.mock[`.primary.tasktypes; `sumtil`sleep`fail];
  `.ut.dpsent set ();
  .tst.mock[`.secondary.runtask; {[tid;tt;a] .ut.dpsent,:enlist (tid;tt;a); }];
  / retries are tested in retry_spec.q, so a failed send stays failed here
  .tst.mock[`.primary.retryreasons; `$()];
 };

.tst.desc[".primary.dispatch - pairing"]{
  before{
    .ut.dpmocks[];
    .ut.dpreset 1 2 3;
    };
  should["do nothing when there are no queued tasks"]{
    .primary.dispatch[];
    0 musteq count .ut.dpsent;
    3 musteq exec count i from secondaries where status=`free;
    };
  should["do nothing when no secondary is free"]{
    update status:`busy from `secondaries;
    .ut.dptask each 0 0i;
    .primary.dispatch[];
    0 musteq count .ut.dpsent;
    2 musteq exec count i from tasks where state=`queued;
    };
  should["send one task to each free secondary and leave the rest queued"]{
    .ut.dptask each 5#0i;
    .primary.dispatch[];
    3 musteq count .ut.dpsent;
    3 musteq exec count i from tasks where state=`dispatched;
    2 musteq exec count i from tasks where state=`queued;
    0 musteq exec count i from secondaries where status=`free;
    };
  should["leave spare secondaries free when there are fewer tasks"]{
    .ut.dptask 0i;
    .primary.dispatch[];
    1 musteq count .ut.dpsent;
    2 musteq exec count i from secondaries where status=`free;
    };
  should["never give one secondary two tasks"]{
    .ut.dptask each 6#0i;
    .primary.dispatch[];
    .primary.dispatch[];
    1 musteq max exec count i by secondaryid from tasks where state=`dispatched;
    };
  should["skip busy, stale and closed secondaries"]{
    update status:`busy from `secondaries where id=1;
    update status:`stale from `secondaries where id=2;
    .primary.register `id`pid`host`port!(4;104i;`localhost;45004i);
    update status:`closed, handle:0Ni from `secondaries where id=4;
    .ut.dptask each 4#0i;
    .primary.dispatch[];
    (enlist 3) mustmatch exec secondaryid from tasks where state=`dispatched;
    };
 };

.tst.desc[".primary.dispatch - order"]{
  before{
    .ut.dpmocks[];
    .ut.dpreset enlist 1;
    };
  should["send the highest priority task first"]{
    .ut.dptask 0i;
    hi:.ut.dptask 5i;
    .ut.dptask 1i;
    .primary.dispatch[];
    hi musteq first first .ut.dpsent;
    };
  should["send the oldest task first when priorities are equal"]{
    first3:.ut.dptask each 3#2i;
    .primary.dispatch[];
    (first first3) musteq first first .ut.dpsent;
    };
  should["work through the queue in priority order over several rounds"]{
    ids:.ut.dptask each 1 3 2i;
    {[x] .primary.dispatch[]; update status:`free, currenttask:0N from `secondaries} each til 3;
    (ids 1 2 0) mustmatch first each .ut.dpsent;
    };
 };

.tst.desc[".primary.sendtask - a send that works"]{
  before{
    .ut.dpmocks[];
    .ut.dpreset enlist 1;
    };
  should["mark the secondary busy with the task"]{
    tid:.ut.dptask 0i;
    .primary.sendtask[1;tid];
    `busy musteq secondaries[1]`status;
    tid musteq secondaries[1]`currenttask;
    };
  should["move the task to dispatched with the secondary and time"]{
    tid:.ut.dptask 0i;
    .primary.sendtask[1;tid];
    r:tasks tid;
    `dispatched musteq r`state;
    1 musteq r`secondaryid;
    1b musteq not null r`dispatchedtime;
    };
  should["send runtask the task id, type and unboxed args"]{
    tid:.primary.newtask `tasktype`args!(`sleep;0.5);
    .primary.sendtask[1;tid];
    (enlist (tid;`sleep;0.5)) mustmatch .ut.dpsent;
    };
 };

.tst.desc[".primary.sendtask - a send that fails"]{
  before{
    .ut.dpmocks[];
    .ut.dpreset 1 2;
    / no connection on this handle, so neg[h] throws
    update handle:99999i from `secondaries where id=1;
    };
  should["mark the secondary stale with no current task"]{
    tid:.ut.dptask 0i;
    .primary.sendtask[1;tid];
    `stale musteq secondaries[1]`status;
    1b musteq null secondaries[1]`currenttask;
    };
  should["fail the task with reason sendfailed"]{
    tid:.ut.dptask 0i;
    .primary.sendtask[1;tid];
    r:tasks tid;
    `failed musteq r`state;
    `sendfailed musteq r`reason;
    1b musteq r[`err] like "send failed*";
    1b musteq not null r`finishedtime;
    1 musteq .ut.dpwarns;
    };
  should["not stop dispatch sending to the other secondaries"]{
    .ut.dptask each 0 0i;
    .primary.dispatch[];
    `stale musteq secondaries[1]`status;
    `busy musteq secondaries[2]`status;
    1 musteq count .ut.dpsent;
    1 musteq exec count i from tasks where state=`failed;
    1 musteq exec count i from tasks where state=`dispatched;
    };
 };