// is this good practice since it isnt under kx?
.timer:use`di.timer;

// run jobs
.timer.init[];


/
this is just for me to haeva  quick reference and some examples of how to use while im doing dev work

// adding job
use .timer.addjob.custom
.timer.addjob.custom[id; func; params; period; mode; opts]
id: job name
func: what function we want to run
params: params to be passed to the function
period: time period running in seconds
mode: when the next run time is (use 2 it runs period seconds after the actual start)
opts: extra options i.e maxruns/maxtime/disableonfail/startattime

eg.
.timer.addjob.custom[`stalecheck; {.primary.check[]}; (); 1; 2; (enlist`disableonfail)!enlist 0b];

// how to check what jobs are scheduled
.timer.getalljobs[]

// how to start
.timer.init starts all jobs running

\