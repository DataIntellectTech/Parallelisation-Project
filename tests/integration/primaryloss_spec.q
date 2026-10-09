// Claude
/ end to end: when the primary dies, its secondaries exit through their own .z.pc
/ kill -9 means the primary's .z.exit never runs, so this checks the secondaries clean themselves up
system "l tests/helpers/it.q";

.tst.desc["end to end: the primary dies"]{
  should["take its secondaries with it"]{
    .it.ready[];
    pids:value .it.q ".primary.spawned";
    primarypid:.it.q ".z.i";
    system "kill -9 ",string primarypid;
    1b musteq .it.waitfor[{[p;x] not any .it.alive each p}[pids];10];
   };
 }; 