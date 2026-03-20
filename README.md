# call_synology_api.sh
Shell script for cleanly managing Synology DSM 7 functions via the command line API. Made to be called as a Scheduled Task.

## Container Management
Supports general Docker container management functions:

The syntax for the command-line is:

```shell
call_synology_api.sh {--container|--project} <name>
    {--start|--stop|--restart|--upgrade|--build|--clean}
    [--no-prune]
    [--no-ansi]
```

You must specify either `--container` or `--project`, followed by an action. Not all actions are available for both projects and containers. (Ex: You can't build a container.)

Option|Argument|Description
---|---|---
`--container`|`<name>`|Name of the Docker container
`--project`|`<name>`|Name of the Docker project
`--start`||Starts the named item
`--stop`||Stops the named item
`--restart`||Restarts the named item
`--upgrade`||Initiates an upgrade of the named item
`--build`||Creates and starts all containers in the project<br/>Only applicable to Projects
`--clean`||Stops and deletes all containers in the project<br/>Only applicable to Projects
`--no-prune`||Do not prune old images during a project upgrade
`--no-ansi`||Force disable ANSI color codes in terminal output

## Examples

```shell
  call_synology_api.sh --project my-project --upgrade
                            # Upgrades "my-project"
  call_synology_api.sh --container plex --restart
                            # Restarts plex
```
