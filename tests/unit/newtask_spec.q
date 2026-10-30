/ unit specs for .primary.newtask, the one way tasks get into the tasks table
/ loads primary.q once (spawning off); each test starts with an empty tasks table
/ the allowed task types are mocked, so the tests don't depend on TASK_TYPES in config
/ run: tests/run.sh tests/unit/newtask_spec.q

setenv[`SPAWN_SECONDARY;enlist "0"];
if[not `primary in key `; system "l src/primary.q"];

.tst.desc[".primary.newtask - accepted tasks"]{
  before{
    `.log.info mock {[x] ::};
    `.log.warn mock {[x] ::};
    `.primary.tasktypes mock `sum`sleep`fail;
    delete from `tasks;
    };
  should["return the next task id"]{
    n:.primary.lasttaskid;
    (n+1) musteq .primary.newtask `tasktype`args!(`sum;1000000);
    (n+1) musteq .primary.lasttaskid;
    };
  should["add the task as queued with its lifecycle columns set"]{
    id:.primary.newtask `tasktype`args!(`sum;1000000);
    r:tasks id;
    `sum musteq r`tasktype;
    `queued musteq r`state;
    0i musteq r`retrycount;
    1b musteq not null r`submittedtime;
    1b musteq null r`secondaryid;
    1b musteq all null r`dispatchedtime`startedtime`finishedtime;
    1b musteq all null r`membefore`memafter;
    "" mustmatch r`err;
    1b musteq null r`reason;
    };
  should["store args and result boxed"]{
    id:.primary.newtask `tasktype`args!(`sum;1000000);
    (enlist 1000000) mustmatch tasks[id]`args;
    1000000 musteq first tasks[id]`args;
    1b musteq null tasks[id]`resultpath;
    1b musteq null tasks[id]`resultbytes;
    };
  should["fill the optional fields from the defaults"]{
    id:.primary.newtask `tasktype`args!(`sleep;200);
    r:tasks id;
    d:.primary.taskdefaults;
    (d`priority) musteq r`priority;
    (d`timeout) musteq r`timeout;
    (d`retriesmax) musteq r`retriesmax;
    1b musteq null r`memestimate;
    };
  should["let the caller override the optional fields"]{
    id:.primary.newtask `tasktype`args`priority`retriesmax`timeout!(`sum;10;5i;1i;00:00:05.000);
    r:tasks id;
    5i musteq r`priority;
    1i musteq r`retriesmax;
    00:00:05.000 musteq r`timeout;
    };
  should["add one task per row when called with each on a table"]{
    n:.primary.lasttaskid;
    ids:.primary.newtask each ([] tasktype:`sum`sleep`fail; args:(100;500;::));
    (n+1 2 3) mustmatch ids;
    3 musteq count tasks;
    };
  should["keep args of different types in the same column"]{
    ids:.primary.newtask each ([] tasktype:`sum`fail`sleep; args:(100;::;`a`b));
    (100;::;`a`b) mustmatch first each tasks[([] taskid:ids)]`args;
    };
  should["show new tasks as queued in the status counts"]{
    .primary.newtask each ([] tasktype:`sum`sum; args:(1;2));
    2i musteq .primary.status[][`taskcounts;`queued];
    };
 };

.tst.desc[".primary.newtask - rejected tasks"]{
  before{
    `.log.info mock {[x] ::};
    `.ut.ntwarns set 0;
    `.log.warn mock {[x] .ut.ntwarns+:1};
    `.primary.tasktypes mock `sum`sleep`fail;
    delete from `tasks;
    };
  should["reject an unknown task type"]{
    1b musteq null .primary.newtask `tasktype`args!(`rm;"-rf /");
    0 musteq count tasks;
    1 musteq .ut.ntwarns;
    };
  should["reject a task with no args"]{
    1b musteq null .primary.newtask enlist[`tasktype]!enlist `sum;
    0 musteq count tasks;
    };
  should["reject a task with no tasktype"]{
    1b musteq null .primary.newtask enlist[`args]!enlist 100;
    0 musteq count tasks;
    };
  should["reject an unknown field"]{
    1b musteq null .primary.newtask `tasktype`args`prority!(`sum;10;1i);
    0 musteq count tasks;
    };
  should["not let the caller set taskid or state"]{
    1b musteq null .primary.newtask `tasktype`args`taskid`state!(`sum;10;999;`done);
    0 musteq count tasks;
    };
  should["reject anything that is not a dict"]{
    1b musteq null .primary.newtask 42;
    1b musteq null .primary.newtask "sum";
    1b musteq null .primary.newtask `sum;
    0 musteq count tasks;
    };
  should["not use up a task id when it rejects"]{
    n:.primary.lasttaskid;
    .primary.newtask `tasktype`args!(`rm;::);
    .primary.newtask 42;
    n musteq .primary.lasttaskid;
    (n+1) musteq .primary.newtask `tasktype`args!(`sum;1);
    };
 };
