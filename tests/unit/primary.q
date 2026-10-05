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
   };
  should["have 1 secondary present"]{
    1 musteq count secondaries;
   };
  should["have id be 1"]{
    1 musteq first exec id from secondaries;
   };
  should["have handle be 6"]{
    0i musteq first exec handle from secondaries;
   };
 };

// should see the above now as stale, uses previous secondary
.tst.desc[".primary.check will say the connection is stale"]{
  before{
    system"sleep 6";
    .primary.check[];
   };
  should["have a status of stale"]{
    `stale musteq first exec status from secondaries where id = 1;
   }; 
 };


// update it with dummy mem data and check lastupdate is new
.tst.desc[".primary.heartbeatcheck updates secondary status to free"]{
  before{
    .primary.heartbeatcheck 100;
   };
  should["return status as free"]{
    `free musteq first exec status from secondaries where id = 1;
   };
  should["have memory as 100"]{
    100 musteq first exec lastmembytes from secondaries where id = 1;
   };
 };

// .z.pc in integration testing
