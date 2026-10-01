// logging lib, output as below
// timestamp procName PID | message

.log.component:`q; // used to determine proc name, master and secondarys overwrite this on start up
.log.handle:0Ni;   // handle to a processes output file

// print log msgs
.log.info:{[msg]
  message:$[10h=type msg; msg; -3!msg];
  logMessage:" " sv (string .z.p; string .log.component; string .z.i; enlist "|"; message);
  .log.toFile logMessage;
 };

// write msg to log file
.log.toFile:{[logMessage] if[not null .log.handle; neg[.log.handle] logMessage] };

// create <dir>/<component>.<dateTime>.log and start mirroring .log.info there too
.log.openFile:{[dir]
  system "mkdir -p ",dir;
  dt:ssr[string .z.p; ":"; "."];
  filePath:hsym `$dir,"/",string[.log.component],".",dt,".log";
  .log.handle:hopen filePath;
  .log.info "logging to ",1_string filePath
 };
