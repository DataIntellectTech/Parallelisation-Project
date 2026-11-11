// run one task: tell the primary it's running, record memory before, run it, record the peak, save the result,
// .Q.gc[], record memory after, and report done or failed with the result's path and size
.secondary.runtask:{[tid; tasktype; args]
  .secondary.send (`.primary.taskupdate; tid; `running; ()!());
  membefore:.mem.readandclear[]`rssanon;    // and reset VmHWM, so the peak read after the task is this task's
  if[not tasktype in key .secondary.approvedtasks;
    :.secondary.fail[tid; `error; "unknown tasktype: ",string tasktype; ([membefore:membefore; memafter:membefore])]];
  // (1b; result) is a success, (0b; error) is a failure: the flag comes first, so no real result can look like a failure
  res:@[{(1b; .secondary.approvedtasks[x] y)}[tasktype;]; args; {[error] (0b; error)}];
  memafter:first exec vmhwm from .mem.read enlist .z.i;
  if[not first res;
    .Q.gc[];
    :.secondary.fail[tid; `error; last res; ([membefore:membefore; memafter:memafter; memaftergc:.secondary.rssanon[]])]];
  saved:.secondary.save[tid; last res];
  res:(::);
  .Q.gc[];
  memaftergc:.secondary.rssanon[];
  if[not first saved;
    :.secondary.fail[tid; `savefailed; "could not save the result: ",last saved; ([membefore:membefore; memafter:memafter; memaftergc:memaftergc])]];
  .log.info "task ",string[tid]," is complete, result saved to ",string saved 1;
  .secondary.send (`.primary.taskupdate; tid; `done; ([resultpath: saved 1; resultbytes: saved 2; membefore: membefore; memafter: memafter; memaftergc: memaftergc]));
 };