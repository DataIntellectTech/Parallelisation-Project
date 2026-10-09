/ unit specs for .primary.status and .primary.countby
/ run with: tests/run.sh tests/unit/status_spec.q

/ load primary.q at the first test, only if no other spec file has already loaded it,
/ with spawning off so no real secondaries start; then put it back to an empty state
/ called at the start of every before
.ut.reset:{[]
  if[not `primary in key `;
    setenv[`SPAWN_SECONDARY;enlist "0"];
    system "l src/primary.q"];
  delete from `secondaries;
  delete from `tasks;
  .primary.spawned:(`long$())!`int$();
  .primary.starttime:.z.P-0D00:01;
 };

/ register a fake secondary with id i (port 45000+i)
.ut.reg:{[i] .primary.register `id`pid`host`port!(i;100i;`localhost;45000i+`int$i)};


.tst.desc[".primary.countby"]{
  before{
    .ut.reset[];
    `.log.info mock {[x] ::};
   };
  should["have the correct count of each state"]{
    .primary.countby[`free`busy`stale`closed;`free`closed`free] mustmatch `free`busy`stale`closed!2 0 0 1i;
   };
  should["give all 0s for an empty list"]{
    .primary.countby[`free`busy`stale`closed; `$()] mustmatch `free`busy`stale`closed!0 0 0 0i;
   };
  should["return ints"]{
    6h musteq type value .primary.countby[`free`busy;`free`free];
   };
 };

.tst.desc[".primary.status"]{
  before{
    .ut.reset[];
    `.log.info mock {[x] ::};
   };
  should["have the correct keys"]{
    s:.primary.status[];
    99h musteq type s;
    `time`uptime`secondaries`seccounts`taskcounts mustmatch key s;
   };
  should["work with no secondaries and no tasks"]{
    s:.primary.status[];
    0 musteq count s`secondaries;
    (`free`busy`stale`closed!0 0 0 0i) mustmatch s`seccounts;
    (`queued`dispatched`running`done`failed!0 0 0 0 0i) mustmatch s`taskcounts;
   };
  should["count secondaries by status"]{
    .ut.reg each 1 2 3 4;
    update status:`closed from `secondaries where id=3;
    update status:`stale from `secondaries where id=4;
    (`free`busy`stale`closed!2 0 1 1i) mustmatch .primary.status[]`seccounts;
   };
  should["count every secondary in some state"]{
    .ut.reg each 1 2 3;
    update status:`busy from `secondaries where id=2;
    (count secondaries) musteq `long$sum .primary.status[]`seccounts;
   };
  should["show one row per secondary with the R1 fields"]{
    .ut.reg each 1 2;
    t:.primary.status[]`secondaries;
    2 musteq count t;
    `id`pid`port`status`spawned`lastseen`lastmembytes mustmatch cols t;
   };
  should["show a just-registered secondary as seen moments ago"]{
    .ut.reg 1;
    1b musteq (first .primary.status[][`secondaries]`lastseen)<00:00:01.000;
   };
  should["show how long ago a quiet secondary was last seen"]{
    .ut.reg 1;
    update lastheartbeat:.z.P-0D00:00:10 from `secondaries where id=1;
    1b musteq (first .primary.status[][`secondaries]`lastseen) within 00:00:10.000 00:00:11.000;
   };
  should["report uptime since start"]{
    1b musteq .primary.status[][`uptime]>=0D00:01;
   };
  should["not change the secondaries table"]{
    .ut.reg each 1 2;
    t0:secondaries;
    .primary.status[];
    t0 mustmatch secondaries;
   };
 };