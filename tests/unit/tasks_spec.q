/ unit specs for the task schema, the task defaults and task ids
/ loads primary.q once (spawning off), each test starts from an empty tasks table
/ run: tests/run.sh tests/unit/tasks_spec.q

setenv[`SPAWN_SECONDARY;enlist "0"];
if[not `primary in key `; system "l src/primary.q"];

.tst.desc[".primary.nexttaskid"]{
  before{
    `.log.info mock {[x] ::};
    };
  should["start at 1 and go up by one"]{
    0 musteq .primary.lasttaskid;
    1 musteq .primary.nexttaskid[];
    1 musteq .primary.lasttaskid;
   };
 };
