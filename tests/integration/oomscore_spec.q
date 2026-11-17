// check the oom score of the secondaries
system "l tests/helpers/it.q";

.tst.desc["check the score of all secondaries oom score"]{
  should["return 1000 for all secondaries"]{
    pids:exec pid from .it.sec[];
    paths:{"/proc/",string[x],"/oom_score_adj"} each pids;
    1b musteq all raze 1000="J"$ {system x}each "cat ",/:paths
  }
 };