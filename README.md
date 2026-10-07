# Parallelisation-Project
Build a pure q parallelisation framework with a master proc that can spin up secondary procs to complete tasks. 

## Primary 
This is the main process which will manage secondaries and tasks

### how to start
Go to the directory and start this will run the default config and start on port `45000`

```bash
cd /home/jrutledge/internalWork/Parallelisation-Project
bash bin/startprimary.sh
```

For starting it interactively do 
```bash
bash config/config.sh     # this is jsut a coipy of deaful.coinfig and im doing it for testing atm, will probs move out
x src/primary.q -p 45000
```

### tables
**secondaries**

This is a table to monitor the secondary processes used for carrying out tasks assigned by the primary. In this table we track key information such as the `status` of a secondary process.

### Secondaries
These will either be ran as part of the intial start up or the primary will spin up more as needed. They will take the port number `PRIMARY_PORT` + `id` so `secondary 1` would have a port of `45001` and so on.

### how to start
To bring up 2 secondaries run the below
```bash
cd /home/jrutledge/internalWork/Parallelisation-Project
bash bin/startsecondary.sh 1
bash bin/startsecondary.sh 2
```

## Testing
We will use the qspec testing framework here, i have copied it into the project directly

### how to run unit tests
From the project top level dir, you run the below commands
```bash
tests/run.sh tests/unit                     # a whole folder
tests/run.sh tests/unit/primarytests.q      # one file
```

Example run
```bash
jrutledge@homer:~/internalWork/Parallelisation-Project$ tests/run.sh tests/unit/primary.q 
.

For 1 specifications, 1 expectations were run.
1 passed, 0 failed.  0 errors.
jrutledge@homer:~/internalWork/Parallelisation-Project$ 
```

### how to run integration tests
From project top level dir run the below commands
```bash
bash tests/integration.sh
```
Example output
```bash
jrutledge@homer:~/internalWork/Parallelisation-Project$ bash tests/integration.sh

== tests/integration/stale_spec.q
..

For 1 specifications, 2 expectations were run.
2 passed, 0 failed.  0 errors.
tests/integration.sh: line 25: 2899594 Killed                  "$Q" src/primary.q -p "$PRIMARY_PORT" < /dev/null >> "$LOG_DIR/primary.log" 2>&1

== tests/integration/stop_spec.q
..

For 1 specifications, 2 expectations were run.
2 passed, 0 failed.  0 errors.
tests/integration.sh: line 25: 2899874 Killed                  "$Q" src/primary.q -p "$PRIMARY_PORT" < /dev/null >> "$LOG_DIR/primary.log" 2>&1

integration: all 2 spec files passed
jrutledge@homer:~/internalWork/Parallelisation-Project$ 
```

## AI Usage
1. qspec installation
2. planning it out after i had an intial plan
    - was mostly good think it maybe went into too much detail for version 1
    - got some things i hadnt considered
3. bash scripting, for any bash scripts primary/secondary/testing
4. q usage
    - simpler tasks eg. creating tables
    - used it in the spawning functionality for spawning secondaries from the primary and the testing
    Worked well mostly with a couple of style fixes (reordering so less brackets) and redefining variable names eg. in qspec it used `before` as a variable and had used `value` in another instance



# my notes ignroe in any PR reviews till the end

```
jrutledge@homer:~/internalWork/Parallelisation-Project$ bash bin/startprimary.sh

start primary: port 45000, config config/default.env
startprimary: port 45000, config config/default.env, pid 1362094, log logs/primary.2026.10.05D13.29.29.log

jrutledge@homer:~/internalWork/Parallelisation-Project$ bash bin/startsecondary.sh 1
start secondary: id 1, port 45001, config config/default.env, pid 1362384, log logs/sec1.2026.10.05D13.29.34.log

jrutledge@homer:~/internalWork/Parallelisation-Project$ bash bin/startsecondary.sh 2
start secondary: id 2, port 45002, config config/default.env, pid 1362708, log logs/sec2.2026.10.05D13.29.37.log
jrutledge@homer:~/internalWork/Parallelisation-Project$ 
```

### q stuff
```q
pri:hopen `::45000

sec1:hopen `::45001
```
### create an images folder or stick them all under docs/images and look at referncing them better
![alt text](image.png)