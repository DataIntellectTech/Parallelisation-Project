system "l tests/helpers/it.q";
/ integration: the brief's memory gating - set a low cap, check dispatch pauses and resumes
/ run with: bash tests/integration.sh gating
/ the first wave goes out while memory is under the cap; the cap is crossed while those tasks run,
/ so dispatch has to pause until they finish and gc

.gt.wait:{[f;secs] end:.z.p+`timespan$1e9*secs; while[(not f[]) and .z.p<end; system "sleep 0.2"]; f[]};
/ queue one task per arg on the primary, returns their ids
.gt.submit:{[tt;a] .it.q ({[x] {[tt;a] .primary.newtask `tasktype`args!(tt;a)}[x 0] each x 1}; (tt;a))};
.gt.tasks:{[ids] .it.q ({`taskid xasc 0!select from tasks where taskid in x}; ids)};
.gt.finished:{[ids] all (.gt.tasks ids)[`state] in `done`failed};
.gt.secs:{.it.q ({0!secondaries}; ::)};
.gt.mb:1048576;

.tst.desc["memory gating: dispatch pauses over the cap and resumes under it"]{
  should["have every spawned secondary registered and free"]{
    1b musteq .it.ready[];
    `.gt.n set count .gt.secs[];
    1b musteq .gt.n>1;
    };
  should["start under a low cap, not paused"]{
    / 250MB: idle (a few MB each) is under it, and one 300MB task still running is over it
    .it.q ({`.primary.memcap set x}; 250*.gt.mb);
    0b musteq .it.q ({.primary.overcap[]}; ::);
    0 musteq .it.q ({.primary.pausecount}; ::);
    };
  should["pause while the first wave holds memory, then resume and finish every task"]{
    / two waves: 300MB each, held for 2 to 5 seconds, so the first one to finish frees a secondary while others still hold memory
    n2:2*.gt.n;
    `.gt.ids set .gt.submit[`hold; ([] mb:n2#300; secs:n2#2 3 4 5)];
    1b musteq not any null .gt.ids;
    1b musteq .gt.wait[{.gt.finished .gt.ids}; 90];
    1b musteq 0<.it.q ({.primary.pausecount}; ::);
    1b musteq 0D<.it.q ({.primary.pausedtotal}; ::);
    };
  should["end resumed, with every task done"]{
    0b musteq .it.q ({.primary.paused}; ::);
    1b musteq all `done=(.gt.tasks .gt.ids)`state;
    };
  should["have held the second wave back until the whole first wave had finished"]{
    t:`dispatchedtime xasc .gt.tasks .gt.ids;
    first1:.gt.n#t;
    next1:first .gt.n _ t;
    / without the gate, the next task would go as soon as the first task finished and freed its secondary
    1b musteq next1[`dispatchedtime]>=max first1`finishedtime;
    };
  };