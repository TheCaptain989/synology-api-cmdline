# synology-api-cmdline
Shell script for cleanly managing Synology DSM 7 functions via the command line API. Made to be called as a Scheduled Task.

- Currently ONLY upgrades all upgradable images in a Docker project and then rebuilds the project.

Usage: `./upgrade_docker_project.sh --project <project_name>`
