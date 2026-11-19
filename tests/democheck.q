/ Runs the demo's steps (docs/demo.md, sections 1-8 and 10) against a real primary, and says PASS or FAIL for each.
/ Started by tests/democheck.sh, which starts a fresh primary under the cgroup and stops everything afterwards.

.dc.h:hopen "J"$getenv`PRIMARY_PORT;
.dc.n:"J"$getenv`NUM_SECONDARYS;
.dc.mb:1048576;
.dc.fails:0;

/ say PASS or FAIL for one check
.dc.check:{[name;ok] -1 $[ok~1b;"PASS  ";"FAIL  "],name; if[not ok~1b; .dc.fails+:1];};
/ run one section; an error in it counts as a fail, and the next section still runs
.dc.section:{[name;f] -1 "\n== ",name; @[f;::;{[n;e] -1 "FAIL  ",n," stopped with an error: ",e; .dc.fails+:1}[name]];};
/ call f[] until it's true or secs seconds pass, and return the last result
.dc.wait:{[f;secs] end:.z.p+secs*0D00:00:01; while[(not r:f[]) and .z.p<end; system "sleep 0.2"]; r};
/ a job's state; wait for a job to finish
.dc.state:{[j] .dc.h({jobs[x][`state]};j)};
.dc.waitjob:{[j;secs] .dc.wait[{[j;x] .dc.state[j] in `done`failed}[j]; secs]; .dc.state j};
/ how many secondaries have status s; wait for all of them to be free
.dc.count:{[s] .dc.h({count select from secondaries where status=x};s)};
.dc.allfree:{[secs] .dc.wait[{.dc.n=.dc.count`free}; secs]};
/ secondary 8's status and pid
.dc.sec8:{[c] .dc.h({first ?[secondaries;enlist (=;`id;8);();x]};c)};
/ submit a job: its id, or its error message as a string
.dc.submit:{[tt;args;params] @[.dc.h;(`.primary.newjob;tt;args;params);{x}]};
/ true if string e contains s
.dc.has:{[e;s] $[10h=type e; 0<count e ss s; 0b]};
/ the cgroup's oom_kill count
.dc.oomkills:{l:.dc.h({system "cat ",.primary.cgroupdir,"/memory.events"};::); "J"$last " " vs first l where l like "oom_kill *"};

.dc.section["0  secondaries up"; {
  .dc.check["all secondaries registered and free"; .dc.allfree 30];
 }];

.dc.section["1  two memory caps"; {
  .dc.check["memory.max is CGROUP_MEM_LIMIT"; (getenv`CGROUP_MEM_LIMIT)~first .dc.h({system "cat ",.primary.cgroupdir,"/memory.max"};::)];
  .dc.check["memcap is GLOBAL_MEM_LIMIT"; ("J"$getenv`GLOBAL_MEM_LIMIT)=.dc.h".primary.memcap"];
 }];

.dc.section["2  run a job"; {
  .dc.days:.dc.h({asc d where not null d:"D"$string key hsym`$getenv`HDB_DIR};::);
  .dc.check["50 days in the HDB"; 50=count .dc.days];
  .dc.j:.dc.h(`.primary.newjob;`vwap;.dc.days;()!());
  .dc.check["vwap job done"; `done=.dc.waitjob[.dc.j;120]];
  took:.dc.h({exec first finishedtime-submittedtime from jobs where jobid=x};.dc.j);
  -1 "      took ",string[took],$[took>0D00:00:05;"  (cold cache: this run has warmed it)";""];
 }];

.dc.section["4  memory for each task"; {
  .dc.jm:.dc.h(`.primary.newjob;`hold;([] mb:8#300; secs:8#5);()!());
  .dc.check["8 busy while they run"; .dc.wait[{8=.dc.count`busy};3]];
  .dc.check["hold job done"; `done=.dc.waitjob[.dc.jm;30]];
  t:.dc.h({select membefore, memafter, memaftergc from tasks where jobid=x};.dc.jm);
  .dc.check["each task peaks at about 300MB"; all t[`memafter] within .dc.mb*290 330];
  .dc.check["about 2MB before each task and after its gc"; all (t[`membefore],t`memaftergc)<.dc.mb*20];
 }];

.dc.section["5  memory-aware dispatch"; {
  .dc.h".primary.memcap:1073741824";
  .dc.jv:.dc.h(`.primary.newjob;`hold;([] mb:8#300; secs:8#3);()!());
  st:.dc.waitjob[.dc.jv;30];
  .dc.h".primary.memcap:",getenv`GLOBAL_MEM_LIMIT;
  .dc.check["hold job done"; `done=st];
  t:.dc.h({select memestimate, dispatchedtime from tasks where jobid=x};.dc.jv);
  .dc.check["each task's estimate is the learnt peak, about 300MB"; all t[`memestimate] within .dc.mb*290 330];
  waves:value count each group floor 1e-9*`long$t[`dispatchedtime]-min t`dispatchedtime;
  .dc.check["sent 3, 3, 2 under a 1GB cap"; 3 3 2~waves];
  .dc.check["memcap back to GLOBAL_MEM_LIMIT"; ("J"$getenv`GLOBAL_MEM_LIMIT)=.dc.h".primary.memcap"];
 }];

.dc.section["6  priority"; {
  .dc.jl:.dc.h(`.primary.newjob;`sleep;40#3;()!());
  .dc.ju:.dc.h(`.primary.newjob;`sumtil;1000 2000 3000;([priority:10]));
  .dc.check["urgent job done"; `done=.dc.waitjob[.dc.ju;10]];
  .dc.check["while the long job is still running"; `running=.dc.state .dc.jl];
  .dc.check["long job done"; `done=.dc.waitjob[.dc.jl;30]];
 }];

.dc.section["7.1  a timeout"; {
  .dc.jt:.dc.h(`.primary.newjob;`sleep;enlist 20;([timeout:00:00:05.000]));
  .dc.check["job failed after about 5s"; `failed=.dc.waitjob[.dc.jt;15]];
  t:.dc.h({first select reason, retrycount from tasks where jobid=x};.dc.jt);
  .dc.check["reason timeout, not retried"; (`timeout;0i)~t`reason`retrycount];
  .dc.check["its secondary restarted"; .dc.allfree 15];
 }];

.dc.section["7.2  out of memory"; {
  k:.dc.oomkills[];
  .dc.jo:.dc.h(`.primary.newjob;`hold;([] mb:(3#100),6000,8#100; secs:12#5);()!());
  .dc.check["job failed"; `failed=.dc.waitjob[.dc.jo;90]];
  t:.dc.h({select state, reason, retrycount, memestimate from tasks where jobid=x};.dc.jo);
  p:t 3;
  .dc.check["part 4 failed as oom, after one retry"; (`failed;`oom;1i)~p`state`reason`retrycount];
  .dc.check["its retry had the kernel's cap as its estimate"; p[`memestimate]="J"$getenv`CGROUP_MEM_LIMIT];
  .dc.check["the other 11 parts done"; all `done=(t`state) _ 3];
  .dc.check["the kernel killed it twice"; (k+2)=.dc.oomkills[]];
  .dc.check["the same args refused next time"; .dc.has[.dc.submit[`hold;([] mb:enlist 6000; secs:enlist 5);()!()];"running on their own"]];
  .dc.check["its secondaries restarted"; .dc.allfree 15];
 }];

.dc.section["7.3  a secondary that dies"; {
  .dc.jk:.dc.h(`.primary.newjob;`sleep;16#3;()!());
  .dc.wait[{`busy=.dc.sec8`status};3];
  pid:.dc.sec8`pid;
  system "kill -9 ",string pid;
  .dc.check["job done"; `done=.dc.waitjob[.dc.jk;30]];
  .dc.check["one task lost, retried and done"; 1=.dc.h({count select from tasks where jobid=x, retrycount=1, state=`done};.dc.jk)];
  .dc.check["secondary 8 restarted with a new pid"; .dc.wait[{[p;x] (`free=.dc.sec8`status) and not p=.dc.sec8`pid}[pid];15]];
 }];

.dc.section["8  guard rails"; {
  .dc.check["unknown task type refused"; .dc.has[.dc.submit[`rm;enlist "x";()!()];"unknown task type"]];
  .dc.check["wrong type for priority refused"; .dc.has[.dc.submit[`sumtil;10 20;([priority:`high])];"wrong type for priority"]];
  .dc.check["unknown param refused"; .dc.has[.dc.submit[`sumtil;10 20;([colour:1])];"unknown params"]];
  .dc.check["no args refused"; .dc.has[.dc.submit[`vwap;`date$();()!()];"no args"]];
  .dc.check["primary still answering"; 1b~.dc.h"1b"];
 }];

.dc.section["10  results"; {
  .dc.paths:.dc.h(`.primary.jobpaths;.dc.j);
  .dc.check["one result file per task"; 50=count .dc.paths];
  .dc.r:raze get each .dc.paths;
  .dc.check["results load and combine"; 0<count .dc.r];
  .dc.check["a failed job has no paths"; .dc.has[@[.dc.h;(`.primary.jobpaths;.dc.jo);{x}];"is failed"]];
  @[hclose;.dc.h;::];
  system "bin/stopall.sh ",getenv[`DEMOCONFIG]," > /dev/null 2>&1";
  .dc.check["primary stopped"; 0b~@[{hclose hopen x; 1b};"J"$getenv`PRIMARY_PORT;{0b}]];
  .dc.check["results still load without the primary"; .dc.r~raze get each .dc.paths];
 }];

-1 "\n",$[.dc.fails; string[.dc.fails]," check(s) failed"; "all checks passed"];
exit `int$0<.dc.fails;