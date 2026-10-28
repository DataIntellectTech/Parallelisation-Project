// tables for the primary process

// monitor the secondary procs 
secondaries : ([id: `long$()]
  handle:           `int$();
  pid:              `int$();
  host:             `$();
  port:             `int$();
  status:           `$();            // `free`busy`stale`closed
  lastheartbeat:    `timestamp$();
  lastmembytes:     `long$();
  consecutivefails: `int$();
  healthy:          `boolean$();
  spawned:          `boolean$();     // if the primary created it or it was up from before
  starttime:        `timestamp$();
  registeredtime:   `timestamp$();
  tasktypes:        ();
  currenttask:      `long$();
  rssanon:          `long$();       // in bytes
  vmrss:            `long$();       // in bytes
  memtime:          `timestamp$()
 );

// monitor the tasks that are being carried out
tasks : ([taskid: `long$()]
  tasktype:       `$();
  args:           ();
  priority:       `int$();
  submittedtime:  `timestamp$();
  memestimate:    `long$();
  timeout:        `time$();
  retriesmax:     `int$();
  retrycount:     `int$();
  state:          `$();            // `queued`dispatched`running`done`failed
  secondaryid:    `long$();
  dispatchedtime: `timestamp$();
  startedtime:    `timestamp$();
  finishedtime:   `timestamp$();
  membefore:      `long$();
  memafter:       `long$();
  err:            (); 
  reason:         `$();            // `timeout`oom`error`lost`sendfailed
  resultpath:     `$();
  resultbytes:    `long$();
  jobid:          `long$()
 );

// one row per memory poll, bounded to the last .primary.memhistorymax rows
memhistory : ([] 
  time:         `timestamp$();
  total:        `long$();
  primary:      `long$();
  secondaries:  `long$();
  busy:         `int$()
 );

// groups of tasks submitted together; when every part is done their results are combined into one
jobs : ([jobid: `long$()]
  tasktype:       `$();
  ntasks:         `int$();
  state:          `$();
  submittedtime:  `timestamp$();
  finishedtime:   `timestamp$();
  combinetask:    `long$();        // taskid of the combine task, null until it is queued
  resultpath:     `$();            // the combined result, null until the job is done
  resultbytes:    `long$();
  err:            ()               // why the job failed, "" when it hasn't
 );