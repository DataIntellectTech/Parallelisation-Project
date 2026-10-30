// Claude
/ end to end: a frozen (SIGSTOP) secondary stays connected but stops heartbeating
system "l tests/helpers/it.q";

.tst.desc["end to end: a secondary goes quiet"]{
  should["mark a frozen secondary stale and leave the other free"]{
    .it.ready[];
    `.it.frozen set first exec pid from .it.sec[] where id=2;
    system "kill -STOP ",string .it.frozen;
    1b musteq .it.waitfor[{`stale~.it.status 2};10];
    `free musteq .it.status 1;
   };
  should["mark it free again once it heartbeats"]{
    system "kill -CONT ",string .it.frozen;
    1b musteq .it.waitfor[{`free~.it.status 2};10];
   };
 };