#!/bin/bash

# Shell script to cleanly managing Synology DSM 7 functions from the command line. Made to be called as a scheduled Task.
#  https://github.com/TheCaptain989/synology-api-cmdline

# Currently ONLY upgrades all upgradable images in a Docker project and then rebuilds the project.
# TODO: Add functionality

# Usage: ./upgrade_docker_project.sh --project <project_name>

# Exit codes
#  0 - Success
#  1 - Unknown command-line argument
#  2 - API error (e.g. project not found, upgrade failed, etc.)

### Functions
function main {
  # Main script execution
  process_command_line "$@"
  echo "-== Starting upgrade process for $PROJECT_NAME project... ==-"

  # Get project ID
  project_id=$(get_project_id "$PROJECT_NAME")
  return_code=$?
  if [ $return_code -ne 0 ]; then
    exit $return_code
  fi
  echo "Docker Project ID: $project_id"
  
  # Get list of upgradable images in the project
  upgradable_images=$(get_upgradable_images)
  return_code=$?
  if [ $return_code -ne 0 ]; then
    exit $return_code
  fi
  if [ -z "$upgradable_images" ]; then
    echo "No upgradable images found." >&2
    exit 0
  fi
  printf "Upgradable Images: %s" "$upgradable_images" | tr "\n" ","; echo ""

  # Upgrade all upgradable images in the project
  upgrade_images "$upgradable_images"
  return_code=$?
  if [ $return_code -ne 0 ]; then
    exit $return_code
  fi

  # Rebuild the project to apply the image upgrades
  build_project "$project_id"
  return_code=$?
  if [ $return_code -ne 0 ]; then
    exit $return_code
  fi

  # Remove old images that are no longer used by any containers
  prune_images
  return_code=$?
  if [ $return_code -ne 0 ]; then
    exit $return_code
  fi

  echo "-== Upgrade process completed for $PROJECT_NAME project! ==-"
}
function usage {
  # Short usage

  usage="$0 --project <project_name>"
  echo "$usage" >&2
}
function process_command_line {
  # Process command line arguments

  while (( "$#" )); do
    case "$1" in
      --project)
        # Docker project name
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 1
        fi
        export PROJECT_NAME="$2"
        shift 2
      ;;
      *)
        echo "Error|Unknown option: $1" >&2
        usage
        exit 1
      ;;
    esac
  done

  if [ -z "$PROJECT_NAME" ]; then
    echo "Error: --project argument is required."
    usage
    exit 1
  fi
}
function call_api {
  # Call the Synology API

  local endpoint="$1" # Ex: SYNO.Docker.Project
  local method="$2"   # Ex: list
  local -a syno_data_args=() # Use an array for susequent arguments

  # Process additional arguments as key=value pairs
  shift 2
  while (( "$#" )); do
    if [[ "$1" == *=* ]]; then
      syno_data_args+=("$1")
    else
      echo "Error: Invalid argument format: $1. Expected key=value." >&2
      exit 1
    fi
    shift
  done
  
  local api_response
  api_response=$(synowebapi -s --exec api="$endpoint" version=1 method="$method" outfile=/dev/null "${syno_data_args[@]}")
  local return_code=$?
  if [ $return_code -ne 0 ]; then
    echo "Error: API call failed with return code $return_code" >&2
  fi

  echo "$api_response"
  return $return_code
}
function get_project_id {
  # Get the project ID for the specified docker project name

  local project_name="$1" # Ex: "My Docker Project"

  local response
  response=$(call_api "SYNO.Docker.Project" "list")
  if [ $? -ne 0 ]; then
    echo "Error: Failed to retrieve project list from API." >&2
    exit 2
  fi
  
  local project_id
  project_id=$(echo "$response" | jq -crM '.data | to_entries | map((select(.value.name == "'$project_name'") | .value.id))[]')
  # Ex: project_id=6a35cb96-2227-419d-bf64-9c8e91c69410

  if [ -z "$project_id" ]; then
    echo "Error: Could not find project ID for $project_name" >&2
    exit 2
  fi
  echo "$project_id"
}
function get_upgradable_images {
  # Get a list of upgradable images in the project

  local response
  response=$(call_api "SYNO.Docker.Image" "list" "limit=-1" "offset=0" "show_dsm=false")
  if [ $? -ne 0 ]; then
    echo "Error: Failed to retrieve upgradable image list from API." >&2
    exit 2
  fi

  local upgradable_images
  upgradable_images=$(echo "$response" | jq -crM '.data.images | map(select(.upgradable))[].repository')

  echo "$upgradable_images"
}
function check_upgrade_status {
  # Check the upgrade status of a given task ID

  local task_id="$1" # ID returned from upgrade_start API call

  local response
  response=$(call_api "SYNO.Docker.Image" "upgrade_status" "task_id=\"$task_id\"")
  if [ $? -ne 0 ]; then
    echo "Error: Failed to retrieve upgrade status from API for $task_id." >&2
    exit 2
  fi

  local upgrade_finished
  upgrade_finished=$(echo "$response" | jq -crM ".data.finished")
  echo "$upgrade_finished"
}
function upgrade_images {
  # Upgrade all upgradable images in the project

  local upgradable_images="$1" # Ex: "linuxserver/sonarr\nlinuxserver/radarr\nlinuxserver/lidarr"

  local exit_code=0
  # Use a while loop with IFS set to an empty string and read -r to process each line exactly as is
  # NOTE: Double quotes around repository name avoids NOT JSON error
  while IFS= read -r image; do
    local response
    response=$(call_api "SYNO.Docker.Image" "upgrade_start" "repository=\"$image\"")
    if [ $? -ne 0 ]; then
      echo "Error: Failed to retrieve task ID from API for $image." >&2
      continue
    fi

    local task_id
    task_id=$(echo "$response" | jq -crM ".data.task_id")
    
    echo -n "Upgrading $image"
    local upgrade_finished=false  
    while [ "$upgrade_finished" == "false" ]; do
      echo -n "."
      # Check state
      upgrade_finished=$(check_upgrade_status "$task_id")
      if [ "$upgrade_finished" != "true" -a "$upgrade_finished" != "null" ]; then
        # Wait a few seconds before checking again to avoid spamming the API
        sleep 5
      fi
    done
    if [ "$upgrade_finished" == "true" ]; then
      echo " done"
    else
      echo " error"
      echo "Error: Upgrade failed for $image with status $upgrade_finished" >&2
      exit_code=2
    fi
  done <<< "$upgradable_images"
  return $exit_code
}
function build_project {
  # Rebuilding the project

  local project_id="$1" # Ex: 6a35cb96-2227-419d-bf64-9c8e91c69410

  local response
  response=$(call_api "SYNO.Docker.Project" "build" "id=\"$project_id\"")
  if [ $? -ne 0 ]; then
    echo "Error: Failed to start project upgrade via API." >&2
    exit 2
  fi

  local build_success
  build_success=$(echo "$response" | jq -crM '.success')

  if [ "$build_success" == "true" ]; then
    echo "Project upgrade successful"
  else
    echo "Project upgrade failed"
    exit 2
  fi
}
function clean_project {
  # Clean the project (stop and delete containers)
  
  local project_id="$1" # Ex: 6a35cb96-2227-419d-bf64-9c8e91c69410
  
  local response
  response=$(call_api "SYNO.Docker.Project" "clean" "id=\"$project_id\"")
  if [ $? -ne 0 ]; then
    echo "Error: Failed to start project clean via API." >&2
    exit 2
  fi

  echo "$response"
}
function prune_images {
  # Clean up unused images

  local response
  response=$(call_api "SYNO.Docker.Image" "prune")
  if [ $? -ne 0 ]; then
    echo "Error: Failed to prune images via API." >&2
    exit 2
  fi
  
  local message
  message=$(echo "$response" | jq -crM '(.data.ImagesDeleted|length) as $count | (.data.SpaceReclaimed | tostring | gsub("(?<=\\d)(?=(\\d{3})+(?!\\d))"; ",")) as $space | "\($count) images deleted saving \($space) bytes."')
  echo "$message"
}

# Do not execute if this script is being sourced from a test script
if [[ ! "${BASH_SOURCE[1]}" =~ test_.*\.sh$ ]]; then
  main "$@"
fi
