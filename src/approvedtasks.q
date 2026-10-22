// this is a file containing any approved task
// we define an empty dict at the top, then a task then after we add this to the approved task
// all tasks that needs several args should be passed as a dict

.secondary.approvedtasks:()!();

// these are the test tasks before we define ones that would actually be useful

.task.sumtil:{sum til x};
.secondary.approvedtasks[`sumtil]:.task.sumtil;

.task.sleep:{system"sleep ",string x};
.secondary.approvedtasks[`sleep]:.task.sleep;

.task.fail:{'`fail};
.secondary.approvedtasks[`fail]:.task.fail;

// actual useful ones
// lets add in a vwap where each secondary will do it for a different month for a time period
// means if we start with 4 secondarys, the primary needs to spin up 8 more if we are doing it over a year
// we will also need to combine the results correctly
// params is just a dict with sdate and edate
.task.vwap:{[d]
  select vwap: size wavg price by date,sym from trades where date = d
 };
.secondary.approvedtasks[`vwap]:.task.vwap;