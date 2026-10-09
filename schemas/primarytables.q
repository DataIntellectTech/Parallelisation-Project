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
  currenttask:      `long$()
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
  reason:         `$();            // `timeout`unknown`oom
  result:         ()
 );