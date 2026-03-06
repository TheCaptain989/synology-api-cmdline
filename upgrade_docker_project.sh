#!/bin/bash

# Shell script to cleanly managing Synology DSM 7 functions from the command line. Made to be called as a scheduled Task.
#  https://github.com/TheCaptain989/synology-api-cmdline

# Currently ONLY upgrades all upgradable images in a Docker project and then rebuilds the project.
# TODO: Make everything more modular and add functions

# Usage: ./upgrade_docker_project.sh --project <project_name>

# Process command line arguments
while (( "$#" )); do
  case "$1" in
    --project)
      # Docker project name
      if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
        echo "Error|Invalid option: $1 requires an argument." >&2
        exit 1
      fi
      export PROJECT_NAME="$2"
      shift 2
    ;;
    *)
      echo "Error|Unknown option: $1" >&2
      exit 1
    ;;
  esac
done

if [ -z "$PROJECT_NAME" ]; then
  echo "Error: --project argument is required."
  exit 1
fi

echo "-== Starting upgrade process for $PROJECT_NAME project... ==-"

# Get docker project ID
project_id=$(synowebapi -s --exec api=SYNO.Docker.Project version=1 method=list | jq -crM '.data | to_entries | map((select(.value.name == "'$PROJECT_NAME'") | .value.id))[]')
# project_id=6a35cb96-2227-419d-bf64-9c8e91c69410

if [ -z "$project_id" ]; then
  echo "Error: Could not find project ID for $PROJECT_NAME"
  exit 1
fi
echo "Docker Project ID: $project_id"

# Check for upgradable images
upgradable_images=$(synowebapi -s --exec api=SYNO.Docker.Image version=1 method=list limit=-1 offset=0 show_dsm=false | jq -crM '.data.images | map(select(.upgradable))[].repository')

if [ -z "$upgradable_images" ]; then
  echo "No upgradable images found."
  exit 0
fi

echo "Upgradable Images:"
echo "$upgradable_images"

# Use a while loop with IFS set to an empty string and read -r to process each line exactly as is
# NOTE: Double quotes around repository name avoids NOT JSON error
while IFS= read -r image; do
  task_id=$(synowebapi -s --exec api=SYNO.Docker.Image version=1 "repository=\"$image\"" method=upgrade_start | jq -crM ".data.task_id")
  echo "Upgrade started for $image, task ID: $task_id"
  upgrade_finished=false  
  while [ "$upgrade_finished" == "false" ]; do
    # Wait a few seconds before checking the status
    sleep 5
    # Check state
    upgrade_finished=$(synowebapi -s --exec api=SYNO.Docker.Image version=1 "task_id=\"$task_id\"" method=upgrade_status | jq -crM ".data.finished")
    echo "Upgrade status for $image: $upgrade_finished"
  done
done <<< "$upgradable_images"

# Upgrade the project
project_success=$(synowebapi -s --exec api=SYNO.Docker.Project version=1 "id=\"$project_id\"" method=build_stream | jq -crM '.success')

if [ "$project_success" == "true" ]; then
  echo "Project upgrade successful"
else
  echo "Project upgrade failed"
  exit 1
fi

# Clean the project (stop and delete containers)
# synowebapi --exec api=SYNO.Docker.Project version=1 "id=\"$project_id\"" method=clean_stream

# Clean up unused images
message=$(synowebapi -s --exec api=SYNO.Docker.Image version=1 method=prune | jq -crM '(.data.ImagesDeleted|length) as $count | (.data.SpaceReclaimed | tostring | gsub("(?<=\\d)(?=(\\d{3})+(?!\\d))"; ",")) as $space | "\($count) images deleted saving \($space) bytes."')
echo "$message"

echo "-== Upgrade process completed for $PROJECT_NAME project! ==-"
