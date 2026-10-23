/ unit specs for src/common/mem.q: reading memory figures from /proc, and resetting VmHWM
/ loads primary.q once (spawning off), which loads mem.q. Uses this process and short-lived sleep processes
/ run: tests/run.sh tests/unit/mem_spec.q

setenv[`SPAWN_SECONDARY;enlist "0"];
if[not `primary in key `; system "l src/primary.q"];

/ start a sleep process in the background and return its pid
.ut.mmsleep:{[] "I"$first system "sh -c 'sleep 30 > /dev/null 2>&1 & echo $!'"};
/ stop processes started by a test
.ut.mmkill:{[pids] if[count pids; system "sh -c 'kill ",(" " sv string pids)," 2>/dev/null; true'"]};

.tst.desc[".mem.read - this process"]{
  before{
    `.log.warn mock {[x] ::};
    };
  should["return one row for the current process"]{
    r:.mem.read enlist .z.i;
    1 musteq count r;
    .z.i musteq first r`pid;
    };
  should["have the agreed columns and types"]{
    (exec c!t from meta .mem.read enlist .z.i) mustmatch `pid`rssanon`vmrss`vmhwm!"ijjj";
    };
  should["give figures in bytes that fit together"]{
    r:first .mem.read enlist .z.i;
    / a q process is at least a megabyte resident
    1b musteq r[`vmrss]>1048576;
    1b musteq r[`rssanon]>0;
    1b musteq r[`vmrss]>=r`rssanon;
    1b musteq r[`vmhwm]>=r`vmrss;
    };
  should["see rssanon rise with an allocation and fall after the gc"]{
    m0:first exec rssanon from .mem.read enlist .z.i;
    a:til 10000000;
    m1:first exec rssanon from .mem.read enlist .z.i;
    a:0; .Q.gc[];
    m2:first exec rssanon from .mem.read enlist .z.i;
    / 10M longs is about 76MB
    1b musteq (m1-m0)>50*1048576;
    1b musteq (m1-m2)>50*1048576;
    };
 };

.tst.desc[".mem.read - other processes"]{
  before{
    `.log.warn mock {[x] ::};
    `.ut.mmpids set .ut.mmsleep each til 2;
    };
  after{
    .ut.mmkill .ut.mmpids;
    };
  should["read several processes in one call, one row each"]{
    pids:.z.i,.ut.mmpids;
    r:.mem.read pids;
    3 musteq count r;
    (asc pids) mustmatch asc r`pid;
    };
  should["leave out a process that has exited, without an error"]{
    .ut.mmkill 1#.ut.mmpids;
    system "sleep 0.2";
    r:.mem.read .z.i,.ut.mmpids;
    2 musteq count r;
    0b musteq (first .ut.mmpids) in r`pid;
    };
  should["return an empty table when every process has exited"]{
    .ut.mmkill .ut.mmpids;
    system "sleep 0.2";
    r:.mem.read .ut.mmpids;
    0 musteq count r;
    (cols .mem.empty) mustmatch cols r;
    };
 };

.tst.desc[".mem.read - nothing to read"]{
  should["return an empty table for an empty list"]{
    r:.mem.read `int$();
    .mem.empty mustmatch r;
    };
 };

.tst.desc[".mem.clearhwm"]{
  before{
    `.ut.mmwarns set 0;
    `.log.warn mock {[x] .ut.mmwarns+:1};
    };
  should["reset vmhwm to about the current vmrss"]{
    / push the peak up, then free it
    a:til 10000000; a:0; .Q.gc[];
    r0:first .mem.read enlist .z.i;
    1b musteq (r0[`vmhwm]-r0`vmrss)>50*1048576;
    .mem.clearhwm[];
    r1:first .mem.read enlist .z.i;
    1b musteq (r1[`vmhwm]-r1`vmrss)<10*1048576;
    0 musteq .ut.mmwarns;
    };
  should["record the peak of what ran after the reset"]{
    .mem.clearhwm[];
    a:til 10000000; a:0; .Q.gc[];
    r:first .mem.read enlist .z.i;
    1b musteq (r[`vmhwm]-r`vmrss)>50*1048576;
    };
 };
