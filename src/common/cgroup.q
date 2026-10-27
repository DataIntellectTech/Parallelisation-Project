// Claude minor edits
// the cgroup v2 directory this primary and the secondaries it spawns run in, e.g. /sys/fs/cgroup/user.slice/.../qfw.scope
// "" if it can't be found. Its memory.events file counts kernel OOM kills (only meaningful under a MemoryMax limit)
.cgroup.dir:{
  l:@[system; "cat /proc/",string[.z.i],"/cgroup"; {[e] ()}];
  l:l where l like "0::*";
  $[count l; "/sys/fs/cgroup",3_first l; ""]
 }[];


 // how many processes the kernel has killed for memory in cgroup directory d (the oom_kill line of its memory.events)
// 0N if it can't be read: no directory, not cgroup v2, or no memory controller
.cgroup.oomkills:{[d]
  if[not count d; :0N];
  l:@[system; "cat ",d,"/memory.events 2>/dev/null"; {[e] ()}];
  l:l where l like "oom_kill *";
  $[count l; "J"$last " " vs first l; 0N]
 };

