// Claude
/ helpers for the integration specs: a client connection to the primary and a few readers
/ not a spec itself: it lives outside the folders qspec is pointed at

.it.ep:`$"::",getenv`PRIMARY_PORT;
.it.n:"J"$getenv`NUM_SECONDARYS;
.it.h:0Ni;

/ a handle to the primary, opened on first use (retries for up to 10s)
.it.connect:{
  if[not null .it.h;:.it.h];
  n:0;
  while[n<50;
    h:@[hopen;(.it.ep;1000);{[e] 0Ni}];
    if[not null h;.it.h:h;:h];
    system "sleep 0.2";
    n+:1];
  '"could not connect to the primary at ",string .it.ep};

/ run q on the primary and return the result
.it.q:{[s] .it.connect[] s};

/ the primary's secondaries table, unkeyed
.it.sec:{.it.q "0!secondaries"};

/ how many secondaries are free right now
.it.nfree:{t:.it.sec[]; sum t[`status]=`free};

/ status of secondarys id, secid
.it.status:{[secid] t:.it.sec[]; first exec status from t where id=secid};

/ is this pid still running?
.it.alive:{[p] not ()~key hsym `$"/proc/",string p};

/ call f[] every 0.2s until it returns 1b or secs seconds pass; says whether it did
.it.waitfor:{[f;secs]
  n:0;
  while[n<5*secs;
    if[f[];:1b];
    system "sleep 0.2";
    n+:1];
  :0b};

/ wait for every spawned secondary to register as free (up to 20s)
.it.ready:{.it.waitfor[{.it.n<=.it.nfree[]};20]};