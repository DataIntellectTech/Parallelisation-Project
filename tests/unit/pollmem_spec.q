/ unit specs for .primary.pollmem and .primary.totalmem: the primary reads its own and every live secondary's memory
/ loads primary.q once (spawning off). The "secondaries" are registered with the pids of short-lived sleep processes,
/ so .mem.read has real processes to read
/ run: tests/run.sh tests/unit/pollmem_spec.q

setenv[`SPAWN_SECONDARY;enlist "0"];
if[not `primary in key `; system "l src/primary.q"];

/ start a sleep process in the background and return its pid; stop a list of them
.ut.pmsleep:{[] "I"$first system "sh -c 'sleep 30 > /dev/null 2>&1 & echo $!'"};
.ut.pmkill:{[pids] if[count pids; system "sh -c 'kill ",(" " sv string pids)," 2>/dev/null; true'"]};

/ empty the tables, start two sleeps and register them as secondaries 1 and 2
.ut.pmreset:{[]
  delete from `secondaries;
  delete from `memhistory;
  `.ut.pmpids set .ut.pmsleep each til 2;
  {[i;p] .primary.register `id`pid`host`port!(i;p;`localhost;45000i+`int$i)}'[1 2;.ut.pmpids];
 };

.tst.desc[".primary.pollmem"]{
  before{
    `.log.info mock {[x] ::};
    `.log.warn mock {[x] ::};
    .ut.pmreset[];
    };
  after{
    .ut.pmkill .ut.pmpids;
    };
  should["fill in rssanon, vmrss and memtime for every live secondary"]{
    t0:.z.P;
    .primary.pollmem[];
    r:0!secondaries;
    1b musteq all r[`rssanon]>0;
    1b musteq all r[`vmrss]>=r`rssanon;
    1b musteq all r[`memtime]>=t0;
    };
  should["record the primary's own memory"]{
    .primary.pollmem[];
    1b musteq .primary.selfmem>1048576;
    / a fresh read can differ by a few pages, so compare to within 1MB
    1b musteq 1048576>abs .primary.selfmem-first exec rssanon from .mem.read enlist .z.i;
    };
  should["leave a closed secondary alone"]{
    update status:`closed, handle:0Ni from `secondaries where id=2;
    .primary.pollmem[];
    1b musteq null secondaries[2]`rssanon;
    1b musteq null secondaries[2]`memtime;
    1b musteq not null secondaries[1]`rssanon;
    };
  should["give nulls for a secondary whose process has gone"]{
    .ut.pmkill 1#.ut.pmpids;
    system "sleep 0.2";
    .primary.pollmem[];
    1b musteq null secondaries[1]`rssanon;
    1b musteq not null secondaries[2]`rssanon;
    };
  should["add one history row per poll with the total split into primary and secondaries"]{
    .primary.pollmem[];
    .primary.pollmem[];
    2 musteq count memhistory;
    h:last memhistory;
    h[`total] musteq h[`primary]+h`secondaries;
    (exec sum rssanon from secondaries where status<>`closed) musteq h`secondaries;
    };
  should["count busy secondaries in the history"]{
    update status:`busy from `secondaries where id=1;
    .primary.pollmem[];
    1i musteq last memhistory`busy;
    };
  should["keep only the last memhistorymax rows"]{
    `.primary.memhistorymax mock 3;
    do[5; .primary.pollmem[]];
    3 musteq count memhistory;
    };
 };

.tst.desc[".primary.totalmem"]{
  before{
    `.log.info mock {[x] ::};
    `.log.warn mock {[x] ::};
    .ut.pmreset[];
    };
  after{
    .ut.pmkill .ut.pmpids;
    };
  should["be the primary plus every live secondary"]{
    .primary.pollmem[];
    (.primary.selfmem + exec sum rssanon from secondaries) musteq .primary.totalmem[];
    };
  should["leave out closed secondaries"]{
    .primary.pollmem[];
    update status:`closed from `secondaries where id=2;
    (.primary.selfmem + secondaries[1]`rssanon) musteq .primary.totalmem[];
    };
  should["match the latest history row"]{
    .primary.pollmem[];
    (last memhistory`total) musteq .primary.totalmem[];
    };
 };