// Claude
/ end to end: spawning more secondaries by hand on a running primary
/ assumes NUM_SECONDARYS=2 (config/integration.env)
system "l tests/helpers/it.q";

.tst.desc["end to end: spawning more secondaries by hand"]{
  should["refuse an id that's already running"]{
    .it.ready[];
    n:.it.q "count .primary.spawned";
    .it.q ".primary.spawn 1";
    n musteq .it.q "count .primary.spawned";
   };
  should["suggest the next free id"]{
    3 musteq .it.q ".primary.nextid[]";
   };
  should["spawn that id, and it registers as free"]{
    .it.q ".primary.spawn 3";
    1b musteq .it.waitfor[{`free~.it.status 3};10];
   };
 };

