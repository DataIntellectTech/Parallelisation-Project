// Claude
/ end to end: the primary spawns NUM_SECONDARYS secondaries and they register and heartbeat
system "l tests/helpers/it.q";

.tst.desc["end to end: spawned secondaries register and heartbeat"]{
  should["have every spawned secondary register as free"]{
    1b musteq .it.ready[];
   };
  should["mark them as spawned, each with its own handle and no port"]{
    t:.it.sec[];
    (asc exec id from t) mustmatch 1 2;
    1b musteq all exec spawned from t;
    2 musteq count distinct exec handle from t;
    / secondaries don't listen: nothing can connect to them, the primary uses the connection they opened
    (count[t]#0i) mustmatch exec port from t;
   };
  should["record a pid for each that is a running process"]{
    1b musteq all .it.alive each exec pid from .it.sec[];
   };
  should["keep receiving heartbeats"]{
    t0:max .it.sec[]`lastheartbeat;
    system "sleep 2.5";
    1b musteq t0<(max .it.sec[]`lastheartbeat);
   };
 };