//Claude
/ end to end: .primary.stop[] shuts every spawned secondary down
system "l tests/helpers/it.q";

.tst.desc["end to end: stopping the secondaries"]{
  should["leave no secondary processes and every row closed"]{
    .it.ready[];
    pids:value .it.q ".primary.spawned";
    .it.q ".primary.stop[]";                     / synchronous: returns after the grace period
    1b musteq .it.waitfor[{[p;x] not any .it.alive each p}[pids];5];
    1b musteq .it.waitfor[{all `closed=.it.sec[]`status};5];
   };
  should["forget the spawned secondaries"]{
    0 musteq .it.q "count .primary.spawned";
   };
 };