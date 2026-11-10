/ unit specs for the V2 headroom check: .primary.committedmem, .primary.fit and its use in .primary.dispatch
/ loads primary.q once (spawning off). Secondaries are registered on handle 0i, so sends run in this process and
/ .secondary.runtask is mocked to record them. Memory is set by hand: the primary 0, each secondary's rssanon 0,
/ a 1000MB cap; tasks are given their memestimate directly. The spare memory and estimate margin are off
/ (0 and 1) unless a test sets them
/ run: tests/run.sh tests/unit/fit_spec.q

setenv[`SPAWN_SECONDARY;enlist "0"];
if[not `primary in key `; system "l src/primary.q"];

.ut.ftmb:1048576;

/ fresh tables and n secondaries, free and using no memory
.ut.ftreset:{[n]
  system "l schemas/primarytables.q";
  .primary.lasttaskid:0;
  {[i] .primary.register `id`pid`host`port!(i;100i+`int$i;`localhost;0i)} each 1+til n;
  update rssanon:0 from `secondaries;
 };

/ a queued sleep task expected to need mb MB (0N for no estimate); returns its id
.ut.ftnew:{[mb] .primary.newtask `tasktype`args`memestimate!(`sleep;1;$[null mb;0N;mb*.ut.ftmb])};

/ logs silenced, a 1000MB cap, the primary using nothing, the over-the-cap gate off, no spare memory and no
/ estimate margin, sends recorded
.ut.ftmocks:{[]
  .tst.mock[`.log.info; {[x] ::}];
  .tst.mock[`.log.warn; {[x] ::}];
  .tst.mock[`.primary.tasktypes; `sumtil`sleep`fail];
  .tst.mock[`.primary.memcap; 1000*.ut.ftmb];
  .tst.mock[`.primary.selfmem; 0];
  .tst.mock[`.primary.overcap; {[] 0b}];
  .tst.mock[`.primary.minheadroom; 0f];
  .tst.mock[`.primary.estimatemargin; 1f];
  `.ut.ftsent set `long$();
  .tst.mock[`.secondary.runtask; {[tid;tt;a] .ut.ftsent,:tid}];
 };

.tst.desc[".primary.fit and dispatch - sending only what fits"]{
  before{
    .ut.ftmocks[];
    .ut.ftreset 4;
    };
  should["send every task when they all fit"]{
    t:.ut.ftnew each 100 200 300;
    .primary.dispatch[];
    t mustmatch .ut.ftsent;
    };
  should["not hand out the same headroom twice in one dispatch"]{
    t:.ut.ftnew each 600 600;
    .primary.dispatch[];
    (1#t) mustmatch .ut.ftsent;
    `queued musteq tasks[last t]`state;
    };
  should["let a smaller task behind one that doesn't fit go first"]{
    big:.ut.ftnew 800;
    .ut.ftnew 600;
    small:.ut.ftnew 100;
    .primary.dispatch[];
    / 800 goes first (fits in 1000), then 600 doesn't fit in the 200 left, 100 does
    (big,small) mustmatch .ut.ftsent;
    };
  should["count a busy secondary's task estimate as committed"]{
    first1:.ut.ftnew 700;
    .primary.dispatch[];
    next1:.ut.ftnew 400;
    .primary.dispatch[];
    / 700 is still running (estimate 700, rssanon 0), so 400 doesn't fit in the 300 left
    (enlist first1) mustmatch .ut.ftsent;
    `queued musteq tasks[next1]`state;
    };
  should["send the waiting task once the running one finishes"]{
    first1:.ut.ftnew 700;
    .primary.dispatch[];
    next1:.ut.ftnew 400;
    .primary.dispatch[];
    / finishing frees the secondary and its memory, and taskupdate dispatches again
    .primary.taskupdate[first1;`running;()!()];
    .primary.taskupdate[first1;`done;([resultpath:`; resultbytes:0; membefore:0; memafter:0])];
    (first1,next1) mustmatch .ut.ftsent;
    };
  should["always send a task with no estimate"]{
    .ut.ftnew 900;
    unknown:.ut.ftnew 0N;
    .primary.dispatch[];
    1b musteq unknown in .ut.ftsent;
    };
  should["send the first task when nothing is running, even if it seems not to fit"]{
    / 4 secondaries at 100MB each leave 600MB, less than the task's 950MB
    update rssanon:100*.ut.ftmb from `secondaries;
    t:.ut.ftnew 950;
    .primary.dispatch[];
    (enlist t) mustmatch .ut.ftsent;
    };
  should["send as before when there is no cap"]{
    `.primary.memcap mock 0N;
    t:.ut.ftnew each 900 900 900;
    .primary.dispatch[];
    t mustmatch .ut.ftsent;
    };
  should["see a finished task's memory freed straight away, without waiting for a poll"]{
    / a 700MB task on secondary 1 and a small one on secondary 2, so a secondary stays busy
    a:.ut.ftnew 700;
    .ut.ftnew 10;
    .primary.dispatch[];
    / the last poll saw secondary 1 at 700MB while its task ran
    update rssanon:700*.ut.ftmb from `secondaries where id=1;
    b:.ut.ftnew 400;
    / secondary 1 finishes and reports 2MB after its gc: 400 now fits, and goes at once
    .primary.taskupdate[a;`running;()!()];
    .primary.taskupdate[a;`done;([resultpath:`; resultbytes:0; membefore:0; memafter:0; memaftergc:2*.ut.ftmb])];
    1b musteq b in .ut.ftsent;
    };
 };

.tst.desc[".primary.fit - spare memory and the estimate margin"]{
  before{
    .ut.ftmocks[];
    .ut.ftreset 4;
    };
  should["not send a task that would leave less than the spare free"]{
    `.primary.minheadroom mock 0.1;
    a:.ut.ftnew 700;
    b:.ut.ftnew 300;
    .primary.dispatch[];
    / 100MB kept spare: 700 fits in 900, then 300 doesn't fit in the 200 left (it would without the spare)
    (enlist a) mustmatch .ut.ftsent;
    `queued musteq tasks[b]`state;
    };
  should["hold back a task with no estimate when less than the spare is free"]{
    `.primary.minheadroom mock 0.1;
    .ut.ftnew 950;
    .primary.dispatch[];
    / 950 went because nothing was running; with it busy, only 50MB is free, under the 100MB spare
    unknown:.ut.ftnew 0N;
    .primary.dispatch[];
    `queued musteq tasks[unknown]`state;
    };
  should["hold back a task whose estimate plus the margin doesn't fit"]{
    `.primary.estimatemargin mock 1.25;
    .ut.ftnew 10;
    .primary.dispatch[];
    / 990MB left: 800 counts as 1000, so it waits (it would go without the margin)
    big:.ut.ftnew 800;
    .primary.dispatch[];
    `queued musteq tasks[big]`state;
    };
  should["still send a task whose estimate plus the margin fits"]{
    `.primary.estimatemargin mock 1.25;
    .ut.ftnew 10;
    .primary.dispatch[];
    / 990MB left: 790 counts as 988, so it goes
    ok:.ut.ftnew 790;
    .primary.dispatch[];
    1b musteq ok in .ut.ftsent;
    };
  should["still send the first task when nothing is running, whatever the spare and margin"]{
    `.primary.minheadroom mock 0.5;
    `.primary.estimatemargin mock 2f;
    t:.ut.ftnew 600;
    .primary.dispatch[];
    (enlist t) mustmatch .ut.ftsent;
    };
 };

.tst.desc[".primary.committedmem"]{
  before{
    .ut.ftmocks[];
    .ut.ftreset 2;
    };
  should["be the primary plus every secondary's memory when none are busy"]{
    `.primary.selfmem mock 10*.ut.ftmb;
    update rssanon:20*.ut.ftmb from `secondaries;
    (50*.ut.ftmb) musteq .primary.committedmem[];
    };
  should["use a busy secondary's task estimate when it's more than its memory"]{
    .ut.ftnew 300;
    .primary.dispatch[];
    (300*.ut.ftmb) musteq .primary.committedmem[];
    };
  should["use a busy secondary's memory when it's more than its task's estimate"]{
    .ut.ftnew 300;
    .primary.dispatch[];
    update rssanon:500*.ut.ftmb from `secondaries where status=`busy;
    (500*.ut.ftmb) musteq .primary.committedmem[];
    };
  should["count the primary as 0 before its first memory poll"]{
    `.primary.selfmem mock 0N;
    update rssanon:20*.ut.ftmb from `secondaries;
    (40*.ut.ftmb) musteq .primary.committedmem[];
    };
 };