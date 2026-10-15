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