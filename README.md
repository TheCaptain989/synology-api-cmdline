# synology-api-cmdline
Shell script for cleanly managing Synology DSM 7 functions from the command line. Made to be called as a scheduled Task.

- Currently ONLY upgrades all upgradable images in a Docker project and then rebuilds the project.

Usage: `./upgrade_docker_project.sh --project <project_name>`
