/ unit specs for restarting dead secondaries: .primary.respawnsecondary, and the call to it from .z.pc
/ loads primary.q once (spawning off). .primary.spawn is mocked to record the ids it would start, .primary.spawned is
/ mocked to say which ids this primary spawned, and .z.pc is called directly with the handle that closed
/ run: tests/run.sh tests/unit/respawn_spec.q

setenv[`SPAWN_SECONDARY;enlist "0"];
if[not `primary in key `; system "l src/primary.q"];

/ empty the tables and register secondaries with ids ids (all free, all on handle 0i)
.ut.rsreset:{[ids]
  delete from `secondaries;
  delete from `tasks;
  .primary.lasttaskid:0;
  {[i] .primary.register `id`pid`host`port!(i;100i+`int$i;`localhost;45000i+`int$i)} each ids;
 };

/ logs counted, secondaries 1 and 2 spawned by us, up to 3 restarts each, spawns and kills recorded
.ut.rsmocks:{[]
  `.ut.rsinfos`.ut.rswarns set' 0;
  .tst.mock[`.log.info; {[x] if[x like "restarting*"; .ut.rsinfos+:1]}];
  .tst.mock[`.log.warn; {[x] .ut.rswarns+:1}];
  .tst.mock[`.primary.tasktypes; `sumtil`sleep`fail];
  .tst.mock[`.primary.retryreasons; `lost`sendfailed];
  .tst.mock[`.primary.memcap; 0N];
  .tst.mock[`.primary.spawned; 1 2!101 102i];
  .tst.mock[`.primary.respawnmax; 3];
  .tst.mock[`.primary.respawns; (`long$())!`long$()];
  `.ut.rsspawns set `long$();
  .tst.mock[`.primary.spawn; {[n] .ut.rsspawns,:n}];
  .tst.mock[`.secondary.runtask; {[tid;tt;a] ::}];
  `.ut.rskills set `int$();
  .tst.mock[`.os.kill9; {[p] .ut.rskills,:p}];
 };

.tst.desc[".primary.respawnsecondary"]{
  before{
    .ut.rsmocks[];
    / secondaries 1 and 2 have died, as they would have by the time .z.pc calls this
    .ut.rsreset 1 2;
    update status:`closed, handle:0Ni from `secondaries;
    };
  should["restart a secondary this primary spawned"]{
    .primary.respawnsecondary 1;
    (enlist 1) mustmatch .ut.rsspawns;
    1 musteq .primary.respawns 1;
    1 musteq .ut.rsinfos;
    };
  should["count restarts separately for each secondary"]{
    .primary.respawnsecondary each 1 1 2;
    2 musteq .primary.respawns 1;
    1 musteq .primary.respawns 2;
    };
  should["stop restarting a secondary after respawnmax restarts"]{
    do[5; .primary.respawnsecondary 1];
    3 musteq count .ut.rsspawns;
    3 musteq .primary.respawns 1;
    / one warning for each refused restart
    2 musteq .ut.rswarns;
    };
  should["not restart a secondary this primary did not spawn"]{
    .primary.respawnsecondary 5;
    0 musteq count .ut.rsspawns;
    };
  should["never restart when respawnmax is 0"]{
    `.primary.respawnmax mock 0;
    .primary.respawnsecondary 1;
    0 musteq count .ut.rsspawns;
    };
  should["never restart when respawnmax is not set"]{
    `.primary.respawnmax mock 0N;
    .primary.respawnsecondary 1;
    0 musteq count .ut.rsspawns;
    };
  should["do nothing for a null id"]{
    .primary.respawnsecondary 0N;
    0 musteq count .ut.rsspawns;
    };
 };

.tst.desc[".z.pc restarts the secondary that closed"]{
  before{
    .ut.rsmocks[];
    .ut.rsreset enlist 1;
    };
  should["restart a spawned secondary when its connection closes"]{
    .z.pc 0i;
    (enlist 1) mustmatch .ut.rsspawns;
    `closed musteq secondaries[1]`status;
    };
  should["fail its task as lost and then restart it"]{
    tid:.primary.newtask `tasktype`args!(`sleep;10);
    `.primary.retryreasons mock `$();
    .primary.sendtask[1;tid];
    .z.pc 0i;
    `lost musteq tasks[tid]`reason;
    (enlist 1) mustmatch .ut.rsspawns;
    };
  should["not restart anything for a handle that is not a secondary"]{
    .z.pc 77i;
    0 musteq count .ut.rsspawns;
    };
 };

.tst.desc["a timeout followed by .z.pc"]{
  before{
    .ut.rsmocks[];
    .ut.rsreset enlist 1;
    };
  should["leave the task failed as timeout, not lost, and restart the secondary"]{
    tid:.primary.newtask `tasktype`args`timeout!(`sleep;10;00:00:01.000);
    .primary.sendtask[1;tid];
    .primary.taskupdate[tid;`running;()!()];
    update startedtime:.z.P-0D00:00:02 from `tasks where taskid=tid;
    .primary.checktimeouts[];
    / the kill would close the connection, which fires .z.pc
    .z.pc 0i;
    `failed musteq tasks[tid]`state;
    `timeout musteq tasks[tid]`reason;
    0i musteq tasks[tid]`retrycount;
    (enlist 101i) mustmatch .ut.rskills;
    (enlist 1) mustmatch .ut.rsspawns;
    };
 };