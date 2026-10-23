// All Claude after i ran some commands for it

// memory figures from the kernel, used by the primary (to watch every secondary, even a busy one)
// and by secondaries (to record each task's peak). See docs/memory-spike.md for why these figures
// all values are in bytes; /proc reports kB (1024 bytes)

// the fields read from /proc/<pid>/status
// RssAnon = the process's own memory (q's heap as the kernel sees it), what the global cap adds up
// VmRSS = all resident memory (RssAnon + file pages), VmHWM = the high-water mark of VmRSS
.mem.fields:`RssAnon`VmRSS`VmHWM;

// what .mem.read returns when there is nothing to read
.mem.empty:([] pid:`int$(); rssanon:`long$(); vmrss:`long$(); vmhwm:`long$());

// memory figures for a list of pids, one row per pid that is still running
// reads every pid with one cat, so one process start (~4ms) however many pids; read0 can't be used as
// /proc files report size 0. A pid that has exited is left out (cat's error is discarded)
// example: .mem.read 2993539 2993543i
.mem.read:{[pids]
  if[not count pids; :.mem.empty];
  files:" " sv {"/proc/",string[x],"/status"} each pids;
  l:system "sh -c 'cat ",files," 2>/dev/null; true'";
  // each line looks like "VmRSS:\t   12345 kB": the name before the colon, then the first word after it
  k:`$first each ":" vs/: l;
  v:{w:" " vs ssr[last ":" vs x;"\t";" "]; first w where 0<count each w} each l;
  // every status file starts with a Name line, so a running count of Name lines says which process a line is from
  g:sums k=`Name;
  i:where k in `Pid,.mem.fields;
  if[not count i; :.mem.empty];
  t:([] g:g i; k:k i; v:"J"$v i);
  r:(`Pid,.mem.fields)#/:value exec k!v by g from t;
  select pid:`int$Pid, rssanon:1024*RssAnon, vmrss:1024*VmRSS, vmhwm:1024*VmHWM from r
 };

// reset this process's VmHWM to its current VmRSS, so the next reading of vmhwm is the peak since now
// written through sh as clear_refs is write-only and hopen can't open it; uses our own pid, as /proc/self in sh is the shell
.mem.clearhwm:{[]
  @[system; "sh -c 'echo 5 > /proc/",string[.z.i],"/clear_refs'"; {[e] .log.warn "could not reset VmHWM: ",e}];
 };
