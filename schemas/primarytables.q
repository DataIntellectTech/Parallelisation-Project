// tables for the master process

// monitor the secondary procs 
secondaries : ([id: `long$()]
  handle:           `int$();
  pid:              `int$();
  host:             `$();
  port:             `int$();
  status:           `$();            // `idle`busy`stale`disconnected
  lastHeartbeat:    `timestamp$();
  lastMemBytes:     `long$();
  consecutiveFails: `int$();
  healthy:          `boolean$();
  spawned:          `boolean$();     // if the master created it or it was up from before
  startTime:        `timestamp$();
  registeredTime:   `timestamp$();
  taskTypes:        ();
  currentTask:      `long$()
 );

// montiro the tasks that are being carried out
tasks : ([taskId: `long$()]
  taskType:       `$();
  args:           ();
  priority:       `int$();
  submittedTime:  `timestamp$();
  timeoutMs:      `long$();
  retriesMax:     `int$();
  retryCount:     `int$();
  state:          `$();            // `queued`dispatched`running`done`failed
  secondaryId:    `long$();
  dispatchedTime: `timestamp$();
  startedTime:    `timestamp$();
  finishedTime:   `timestamp$();
  err:            (); 
  reason:         `$()             // `timeout`unknown`oom
 );