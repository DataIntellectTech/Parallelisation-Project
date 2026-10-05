system"l src/primary.q";

.tst.desc["check env vars are as excpected"]{
  should["STALE_MS should be 5 seconds"]{
    00:00:05 musteq .primary.stale;
   };
  should["HEARTBEAT_MS should be 1 seconds"]{
    00:00:01 musteq .primary.heartbeat
   };
 };

.tst.desc["can a secondary register with .primary.register"]{
  before{
    `.log.warn mock {};
    `.log.info mock {};
    .primary.register ([id:1; pid:4000i; host:`localhost; port:45001i ]);
    update handle:6i from `secondaries where id = 1; // need to do as we run on handle 0
   };
  should["have 1 secondary present"]{
    1 musteq count secondaries;
   };
  should["have id be 1"]{
    1 musteq first exec id from secondaries;
   };
  should["have handle be 6"]{
    6i musteq first exec handle from secondaries;
   };
 };

// should see the above now as stale
system"sleep 6"
.tst.desc[".primary.check will say the connection is stale"]{
  before{
    system"sleep 6";
    .primary.check[];
   };
  should["have a status of stale"]{
    `stale musteq first exec status from secondaries where id = 1;
   }; 
 };

// can a secondary register
// update it with dummy mem data and check lastupdate is new
// discoonect and test .z.pc
// stale check