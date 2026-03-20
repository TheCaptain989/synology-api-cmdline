# synology-api-cmdline
Shell script for cleanly managing Synology DSM 7 functions via the command line API. Made to be called as a Scheduled Task.

Two scripts

## Upgrade Docker Project
One ONLY upgrades all upgradable images in a Docker project and then rebuilds the project.

Usage: `upgrade_docker_project.sh --project <project_name>`

## General Docker
Supports more general functions:

Usage:

```shell
call_synology_api.sh {--container|--project} <name>
    {--start|--stop|--restart|--upgrade|--build|--clean}
    [--no-prune]
    [--no-ansi]
```

You must specify either `--container` or `--project`, followed by an action. Not all actions are available for both projects and containers. (Ex: You can't build a container.)
