// Claude 
/ end to end: a secondary is killed and the primary's .z.pc marks it closed
system "l tests/helpers/it.q";

.tst.desc["end to end: a secondary is killed"]{
  should["mark it closed and leave the other free"]{
    .it.ready[];
    pid:first exec pid from .it.sec[] where id=1;
    system "kill -9 ",string pid;
    1b musteq .it.waitfor[{`closed~.it.status 1};10];
    `free musteq .it.status 2;
   };
  should["should not have an open handle"]{
    1b musteq null first exec handle from .it.sec[] where id=1;
   };
 };