# Prerequisites 

## Docker

I assume you have intelliJ set up for the below

### Machine Requirements
- Open Task Manager, go to Performance and check you have "Virtualization: Enabled"
- You will also need at least 4GB RAM with *GM recommended, as well as 6GB of free disk space.

### Install WSL 2

Open windows powershell and run the following
```
wsl --install
wsl --update
wsl --version
```
Then restart your machine. Currently WSL 2.1.5 or higher is needed .

### Install Docker

Download docker using the guide here [Get Docker](https://docs.docker.com/desktop/setup/install/windows-install/). Select the below
![img.png](img.png)

### Set up Docker with IntelliJ

1. Click the burger (top left 4 lines), go to settings, choose plugins and search for docker to install it
2. Go to settings, choose Build, Execution, Deployment, then Docker and hit `+` choosing Docker for windows.
3. It should be visible in the service window (Alt+8)

You should now be free to develop