/ end to end: .primary.status called over IPC on a live primary
system "l tests/helpers/it.q";

.it.status:{[] .it.q ".primary.status[]"};

.tst.desc["end to end: status over IPC"]{
  should["return a dictionary from a remote call"]{
    .it.ready[];
    99h musteq type .it.status[];
   };
  should["show every spawned secondary as free"]{
    s:.it.status[];
    .it.n musteq s[`seccounts;`free];
    .it.n musteq count s`secondaries;
   };
  should["show recent heartbeats for all of them"]{
    1b musteq all (.it.status[][`secondaries]`lastseen)<00:00:02.000;
   };
  should["report a positive uptime"]{
    1b musteq .it.status[][`uptime]>0D00:00:00;
   };
  should["count a killed secondary as closed"]{
    pid:first exec pid from .it.status[][`secondaries] where id=1;
    system "kill -9 ",string pid;
    1b musteq .it.waitfor[{1=.it.status[][`seccounts;`closed]};10];
    (.it.n-1) musteq .it.status[][`seccounts;`free];
   };
 };