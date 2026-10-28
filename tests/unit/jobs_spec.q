/ unit specs for jobs: .primary.newjob, .primary.jobcheck (via taskupdate), .primary.canceljob and .primary.getjobresult
/ loads primary.q once (spawning off). No secondaries are registered, so nothing is dispatched: each test moves a
/ job's tasks through their states with .primary.taskupdate, as a secondary would, and saves results by hand
/ run: tests/run.sh tests/unit/jobs_spec.q

setenv[`SPAWN_SECONDARY;enlist "0"];
if[not `primary in key `; system "l src/primary.q"];

.ut.jbdir:"/tmp/qfw-jobs-spec";

/ fresh tables from the schema and an empty results folder
.ut.jbreset:{[]
  system "l schemas/primarytables.q";
  .primary.lasttaskid:0;
  system "rm -rf ",.ut.jbdir;
  system "mkdir -p ",.ut.jbdir;
 };

/ a job of n sumtil tasks with 3 retries each, returns the job id
.ut.jbnew:{[n]
  j:.primary.newjob[`sumtil; 10*1+til n];
  update retriesmax:3i from `tasks where jobid=j;
  j
 };

/ the task ids of job j, in order
.ut.jbtids:{[j] exec taskid from tasks where jobid=j};

/ move a queued task to running, as dispatch and the secondary would
.ut.jbrun:{[tid]
  .primary.taskupdate[tid;`dispatched;()!()];
  .primary.taskupdate[tid;`running;()!()];
 };

/ finish a task as done with result r saved on disk (r is :: for no result)
.ut.jbdone:{[tid;r]
  if[`queued~tasks[tid]`state; .ut.jbrun tid];
  p:$[(::)~r; `; [p:hsym `$.ut.jbdir,"/",string tid; p set r; p]];
  .primary.taskupdate[tid;`done;([resultpath:p; resultbytes:$[null p; 0; hcount p]; membefore:0; memafter:0])];
 };

/ fail a task with reason rsn
.ut.jbfail:{[tid;rsn]
  if[`queued~tasks[tid]`state; .ut.jbrun tid];
  .primary.taskupdate[tid;`failed;([err:"boom"; reason:rsn; membefore:0; memafter:0])];
 };

/ logs silenced except jobcheck's "job N failed: ..." warnings, which are counted
/ KDB-X like throws 'nyi for a * in the middle of a pattern, so match with two patterns that only use * at the ends
.ut.jbmocks:{[]
  .tst.mock[`.log.info; {[x] ::}];
  `.ut.jbfails set 0;
  .tst.mock[`.log.warn; {[x] if[(x like "job*") and x like "*failed:*"; .ut.jbfails+:1]}];
  .tst.mock[`.primary.tasktypes; `sumtil`sleep`fail];
  .tst.mock[`.primary.retryreasons; `lost`sendfailed];
  .tst.mock[`.primary.memcap; 0N];
  .tst.mock[`.primary.lastjobid; 0];
 };

.tst.desc[".primary.newjob"]{
  before{
    .ut.jbmocks[];
    .ut.jbreset[];
    };
  after{
    system "rm -rf ",.ut.jbdir;
    };
  should["create one task per arg, all with the job's id"]{
    j:.primary.newjob[`sumtil; 10 20 30];
    3 musteq count .ut.jbtids j;
    1b musteq all j=exec jobid from tasks;
    };
  should["give each task its own arg, in order"]{
    j:.primary.newjob[`sumtil; 10 20 30];
    10 20 30 mustmatch exec first each args from tasks where jobid=j;
    };
  should["add the job as running with its number of tasks"]{
    j:.primary.newjob[`sumtil; 10 20 30];
    (`running;3i) mustmatch jobs[j]`state`ntasks;
    1b musteq not null jobs[j]`submittedtime;
    };
  should["give each job the next id"]{
    1 2 mustmatch {[x] .primary.newjob[`sumtil; 1 2]} each 1 2;
    };
  should["error for an unknown task type and create nothing"]{
    mustthrow[(); {[] .primary.newjob[`nope; 1 2]}];
    0 musteq count jobs;
    0 musteq count tasks;
    };
  should["error for no args and create nothing"]{
    mustthrow[(); {[] .primary.newjob[`sumtil; ()]}];
    0 musteq count jobs;
    0 musteq count tasks;
    };
 };

.tst.desc[".primary.jobcheck - a job's state follows its tasks"]{
  before{
    .ut.jbmocks[];
    .ut.jbreset[];
    };
  after{
    system "rm -rf ",.ut.jbdir;
    };
  should["leave the job running while some parts are not done"]{
    j:.ut.jbnew 3;
    .ut.jbdone[first .ut.jbtids j; 1];
    `running musteq jobs[j]`state;
    };
  should["mark the job done when every part is done, with the total result size"]{
    j:.ut.jbnew 3;
    .ut.jbdone[;1] each .ut.jbtids j;
    `done musteq jobs[j]`state;
    1b musteq not null jobs[j]`finishedtime;
    (exec sum resultbytes from tasks where jobid=j) musteq jobs[j]`resultbytes;
    };
  should["mark the job failed when a part fails for good, naming the part"]{
    j:.ut.jbnew 3;
    t:.ut.jbtids j;
    .ut.jbfail[t 1; `error];
    `failed musteq jobs[j]`state;
    1b musteq jobs[j][`err] like "task ",string[t 1]," failed (error)*";
    1 musteq .ut.jbfails;
    };
  should["keep the job running when a lost part is retried"]{
    j:.ut.jbnew 3;
    t:.ut.jbtids j;
    .ut.jbfail[first t; `lost];
    `queued musteq tasks[first t]`state;
    `running musteq jobs[j]`state;
    };
  should["finish the job done after a lost part is retried and succeeds"]{
    j:.ut.jbnew 2;
    t:.ut.jbtids j;
    .ut.jbfail[first t; `lost];
    .ut.jbdone[;1] each t;
    `done musteq jobs[j]`state;
    };
  should["not change a failed job when its other parts finish"]{
    j:.ut.jbnew 3;
    t:.ut.jbtids j;
    .ut.jbrun t 1;
    .ut.jbfail[first t; `error];
    .ut.jbdone[t 1; 1];
    `failed musteq jobs[j]`state;
    1 musteq .ut.jbfails;
    };
  should["leave jobs alone for a task submitted on its own"]{
    `.ut.jbtid set .primary.newtask `tasktype`args!(`sumtil;10);
    mustnotthrow[(); {[] .ut.jbdone[.ut.jbtid;1]}];
    0 musteq count jobs;
    };
 };

.tst.desc[".primary.canceljob - the rest of a failed job"]{
  before{
    .ut.jbmocks[];
    .ut.jbreset[];
    };
  after{
    system "rm -rf ",.ut.jbdir;
    };
  should["cancel the queued parts when a part fails"]{
    j:.ut.jbnew 4;
    t:.ut.jbtids j;
    .ut.jbfail[first t; `error];
    `failed`failed`failed mustmatch tasks[([] taskid:1_t)]`state;
    `cancelled`cancelled`cancelled mustmatch tasks[([] taskid:1_t)]`reason;
    };
  should["leave a part that is already running alone"]{
    j:.ut.jbnew 3;
    t:.ut.jbtids j;
    .ut.jbrun t 1;
    .ut.jbfail[first t; `error];
    `running musteq tasks[t 1]`state;
    `failed musteq tasks[t 2]`state;
    };
  should["not retry cancelled parts"]{
    j:.ut.jbnew 3;
    t:.ut.jbtids j;
    .ut.jbfail[first t; `error];
    1b musteq all 0i=exec retrycount from tasks where jobid=j;
    };
 };

.tst.desc[".primary.getjobresult"]{
  before{
    .ut.jbmocks[];
    .ut.jbreset[];
    };
  after{
    system "rm -rf ",.ut.jbdir;
    };
  should["combine the parts' results in task order, whatever order they finished in"]{
    j:.ut.jbnew 3;
    t:.ut.jbtids j;
    .ut.jbdone'[reverse t; (5 6;3 4;1 2)];
    1 2 3 4 5 6 mustmatch .primary.getjobresult j;
    };
  should["combine tables into one table"]{
    j:.ut.jbnew 2;
    t:.ut.jbtids j;
    .ut.jbdone'[t; (([] a:1 2); ([] a:3 4))];
    ([] a:1 2 3 4) mustmatch .primary.getjobresult j;
    };
  should["skip parts that returned no result"]{
    j:.ut.jbnew 3;
    t:.ut.jbtids j;
    .ut.jbdone'[t; (1 2;::;3 4)];
    1 2 3 4 mustmatch .primary.getjobresult j;
    };
  should["error for a job that isn't done"]{
    `.ut.jbj set .ut.jbnew 2;
    mustthrow[(); {[] .primary.getjobresult .ut.jbj}];
    };
  should["error for a failed job"]{
    `.ut.jbj set .ut.jbnew 2;
    .ut.jbfail[first .ut.jbtids .ut.jbj; `error];
    mustthrow[(); {[] .primary.getjobresult .ut.jbj}];
    };
  should["error for a job that doesn't exist"]{
    mustthrow[(); {[] .primary.getjobresult 99}];
    };
 };