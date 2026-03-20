#!/bin/bash

# Shell script to cleanly managing Synology DSM 7 functions from the command line. Made to be called as a scheduled Task.
#  https://github.com/TheCaptain989/synology-api-cmdline

# Exit codes
#  0 - Success
#  1 - Unknown command-line argument
#  2 - API error (e.g. project not found, upgrade failed, etc.)

### Functions
function main {
  # Main script execution
  setup_ansi_colors
  process_command_line "$@"
  
  # Build function variable to be called
  if [ -n "$PROJECT_NAME" ]; then
    local target="project"
    # Get project ID
    local function_arg
    function_arg=$(get_project_id "$PROJECT_NAME")
    local return_code=$?
    [ $return_code -ne 0 ] && { exit $return_code; }
  elif [ -n "$CONTAINER_NAME" ]; then
    local target="container"
    local function_arg
    function_arg="$CONTAINER_NAME"
  fi

  # Execute function
  local called_function="${ACTION}_${target}"
  $called_function "$function_arg"
  local return_code=$?
  [ $return_code -ne 0 ] && { exit $return_code; }
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
      --container)
        # Docker container name
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error: Invalid option: $1 requires an argument." >&2
          usage
          exit 1
        fi
        export CONTAINER_NAME="$2"
        shift 2
      ;;
      --project)
        # Docker project name
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error: Invalid option: $1 requires an argument." >&2
          usage
          exit 1
        fi
        export PROJECT_NAME="$2"
        shift 2
      ;;
      --start)
        export ACTION="start"
        shift
      ;;
      --stop)
        export ACTION="stop"
        shift
      ;;
      --restart)
        export ACTION="restart"
        shift
      ;;
      --upgrade)
        export ACTION="upgrade"
        shift
      ;;
      --build)
        export ACTION="build"
        shift
      ;;
      --clean)
        export ACTION="clean"
        shift
      ;;
      --no-ansi)
        export NOANSI="true"
      ;;
      --no-prune)
        export NOPRUNE="true"
      ;;
      *)
        echo_ansi "Error|Unknown option: $1" >&2
        usage
        exit 1
      ;;
    esac
  done

  if [ -z "$ACTION" ]; then
    echo_ansi "Error: Must specify action option." >&2
    usage
    exit 1
  fi

  if [ -z "$PROJECT_NAME" -a -z "$CONTAINER_NAME" ]; then
    echo_ansi "Error: --project or --container option are required." >&2
    usage
    exit 1
  fi
}
function setup_ansi_colors {
  # Setup ANSI color codes and determine when to use them.
  # Colors should only be used when the script is writing to an interactive terminal.

  export ANSI_RED='\033[0;31m'
  export ANSI_GREEN='\033[0;32m'
  export ANSI_YELLOW='\033[0;33m'
  export ANSI_CYAN='\033[0;36m'
  export ANSI_NC='\033[0m' # No Color
}
function echo_ansi {
  # Apply ANSI colors for terminal output only.
  # Colors are based on the message prefix (Error|, Warn|, Debug|).
  
  local msg="$*"

  local prefix="${msg%%: *}"
  local color=""
  case "$prefix" in
    Error) color="$ANSI_RED" ;;
    Warn)  color="$ANSI_YELLOW" ;;
    Debug) color="$ANSI_CYAN" ;;
  esac
  
  local use_color=false
  if [ -t 1 -a -t 2 ] && [ -z "$NOANSI" ]; then
    use_color=true
  fi
  
  if $use_color && [ -n "$color" ]; then
    builtin echo -e "${color}${msg}${ANSI_NC}"
  else
    builtin echo "$msg"
  fi
}
function call_api {
  # Call the Synology API

  local endpoint="$1" # Ex: SYNO.Docker.Project
  local method="$2"   # Ex: list
  local -a syno_data_args=() # Use an array for subsequent arguments

  # Process additional arguments as key=value pairs
  shift 2
  while (( "$#" )); do
    if [[ "$1" == *=* ]]; then
      syno_data_args+=("$1")
    else
      echo_ansi "Error: Invalid argument format: $1. Expected key=value." >&2
      return 1
    fi
    shift
  done
  
  local api_response
  api_response=$(synowebapi -s --exec api="$endpoint" version=1 method="$method" outfile=/dev/null "${syno_data_args[@]}")
  local return_code=$?
  if [ $return_code -ne 0 ]; then
    echo_ansi "Error: API call failed with return code $return_code" >&2
  fi

  echo "$api_response"
  return $return_code
}
function get_project_id {
  # Get the project ID for the specified docker project name

  local project_name="$1" # Ex: "My Docker Project"

  local response
  response=$(call_api "SYNO.Docker.Project" "list")
  local return_code=$?
  [ $return_code -ne 0 ] && { echo_ansi "Error: Failed to retrieve project list from API." >&2; return $return_code; }
  
  local project_id
  project_id=$(echo "$response" | jq -crM '.data | to_entries | map((select(.value.name == "'$project_name'") | .value.id))[]')

  if [ -z "$project_id" -o "$project_id" == "null" ]; then
    echo_ansi "Error: Could not find project ID for $project_name" >&2
    return 1
  fi
  echo "$project_id"
}
function get_image {
  # Get the image for the specified docker container

  local container_name="$1" # Ex: "radarr"

  local response
  response=$(call_api "SYNO.Docker.Container" "get" "name=\"$container_name\"")
  local return_code=$?
  [ $return_code -ne 0 ] && { echo_ansi "Error: Failed to retrieve container info from API." >&2; return $return_code; }
  
  echo $response >&2
  local image
  image=$(echo "$response" | jq -crM '.data.details.Config.Image')

  if [ -z "$image" -o "$image" == "null" ]; then
    echo_ansi "Error: Could not find image for container $container_name" >&2
    return 1
  fi
  echo "$image"
}
function get_project_images {
  # Get the image for the specified project

  local project_id="$1" # Ex: project_id=6a35cb96-2227-419d-bf64-9c8e91c69410

  local response
  response=$(call_api "SYNO.Docker.Project" "get" "id=\"$project_id\"")

  # Check that the project is running
  local status
  status=$(echo "$response" | jq -crM '.data.status')
  if [ "$status" != "RUNNING" ]; then
    echo_ansi "Error: Project is not running." >&2
    return 1
  fi

  local return_code=$?
  [ $return_code -ne 0 ] && { echo_ansi "Error: Failed to retrieve project info from API." >&2; return $return_code; }
  
  local images
  images=$(echo "$response" | jq -crM '.data.containers[].Config.Image')
  if [ -z "$images" ]; then
    echo_ansi "Error: Could not find images for project." >&2
    return 1
  fi
  echo "$images"
}
function start_container {
  # Start the container

  local container_name="$1" # Ex: radarr

  local response
  response=$(call_api "SYNO.Docker.Container" "start" "name=\"$container_name\"")
  local return_code=$?
  [ $return_code -ne 0 ] && { echo_ansi "Error: Failed to start the container via API." >&2; return $return_code; }

  local success
  success=$(echo "$response" | jq -crM '.success')
  if [ "$success" != "true" ]; then
    echo_ansi "Error: Container start failed" >&2
    return 1
  fi

  echo_ansi "Container start successful"
}
function stop_container {
  # Stop the container

  local container_name="$1" # Ex: radarr

  local response
  response=$(call_api "SYNO.Docker.Container" "stop" "name=\"$container_name\"")
  local return_code=$?
  [ $return_code -ne 0 ] && { echo_ansi "Error: Failed to stop the container via API." >&2; return $return_code; }

  local success
  success=$(echo "$response" | jq -crM '.success')
  if [ "$success" != "true" ]; then
    echo_ansi "Error: Container stop failed" >&2
    return 1
  fi

  echo_ansi "Container stop successful"
}
function restart_container {
  # Restart the container

  local container_name="$1" # Ex: radarr

  local response
  response=$(call_api "SYNO.Docker.Container" "restart" "name=\"$container_name\"")
  local return_code=$?
  [ $return_code -ne 0 ] && { echo_ansi "Error: Failed to restart the container via API." >&2; return $return_code; }

  local success
  success=$(echo "$response" | jq -crM '.success')
  if [ "$success" != "true" ]; then
    echo_ansi "Error: Container restart failed" >&2
    return 1
  fi

  echo_ansi "Container restart successful"
}
function upgrade_container {
  # Upgrade the container

  local container_name="$1" # Ex: radarr
  echo "-== Starting upgrade process for $container_name container... ==-"

  # Get container image
  local image
  image=$(get_image "$container_name")
  local return_code=$?; [ $return_code -ne 0 ] && { return $return_code; }
  image="${image%%:*}"
  echo "Container image: $image"

  # Get list of upgradable images
  local upgradable_images
  upgradable_images=$(get_upgradable_images)
  local return_code=$?; [ $return_code -ne 0 ] && { return $return_code; }

  if ! [[ "$upgradable_images" == *"$image"* ]]; then
    echo_ansi "Error: No upgrade is available for container image $image" >&2
    return 1
  fi

  # Upgrade upgradable image
  upgrade_images "$image"
  local return_code=$?; [ $return_code -ne 0 ] && { return $return_code; }

  # Restart container
  restart_container "$container_name"
  local return_code=$?; [ $return_code -ne 0 ] && { return $return_code; }

  echo "-== Upgrade process completed for $container_name container! ==-"
}
function start_project {
  # Start the project

  local project_id="$1" # Ex: project_id=6a35cb96-2227-419d-bf64-9c8e91c69410

  local response
  response=$(call_api "SYNO.Docker.Project" "start" "id=\"$project_id\"")
  local return_code=$?
  [ $return_code -ne 0 ] && { echo_ansi "Error: Failed to start the project via API." >&2; return $return_code; }

  local success
  success=$(echo "$response" | jq -crM '.success')
  if [ "$success" != "true" ]; then
    echo_ansi "Error: Project start failed" >&2
    return 1
  fi

  echo_ansi "Project start successful"
}
function stop_project {
  # Stop the project

  local project_id="$1" # Ex: project_id=6a35cb96-2227-419d-bf64-9c8e91c69410

  local response
  response=$(call_api "SYNO.Docker.Project" "stop" "id=\"$project_id\"")
  local return_code=$?
  [ $return_code -ne 0 ] && { echo_ansi "Error: Failed to stop the project via API." >&2; return $return_code; }

  local success
  success=$(echo "$response" | jq -crM '.success')
  if [ "$success" != "true" ]; then
    echo_ansi "Error: Project stop failed" >&2
    return 1
  fi

  echo_ansi "Project stop successful"
}
function restart_project {
  # Restart the project

  local project_id="$1" # Ex: project_id=6a35cb96-2227-419d-bf64-9c8e91c69410

  local response
  response=$(call_api "SYNO.Docker.Project" "restart" "id=\"$project_id\"")
  local return_code=$?
  [ $return_code -ne 0 ] && { echo_ansi "Error: Failed to restart the project via API." >&2; return $return_code; }

  local success
  success=$(echo "$response" | jq -crM '.success')
  if [ "$success" != "true" ]; then
    echo_ansi "Error: Project restart failed" >&2
    return 1
  fi

  echo_ansi "Project restart successful"
}
function build_project {
  # Build the project

  local project_id="$1" # Ex: project_id=6a35cb96-2227-419d-bf64-9c8e91c69410

  local response
  response=$(call_api "SYNO.Docker.Project" "build" "id=\"$project_id\"")
  local return_code=$?
  [ $return_code -ne 0 ] && { echo_ansi "Error: Failed to build the project via API." >&2; return $return_code; }

  local success
  success=$(echo "$response" | jq -crM '.success')
  if [ "$success" != "true" ]; then
    echo_ansi "Error: Project build failed" >&2
    return 1
  fi

  echo_ansi "Project build successful"
}
function clean_project {
  # Clean the project (stop and delete containers)
  
  local project_id="$1" # Ex: project_id=6a35cb96-2227-419d-bf64-9c8e91c69410
  
  local response
  response=$(call_api "SYNO.Docker.Project" "clean" "id=\"$project_id\"")
  local return_code=$?
  [ $return_code -ne 0 ] && { echo_ansi "Error: Failed to clean the project via API." >&2; return $return_code; }

  local success
  success=$(echo "$response" | jq -crM '.success')
  if [ "$success" != "true" ]; then
    echo_ansi "Error: Project clean failed" >&2
    return 1
  fi

  echo_ansi "Project clean successful"
}
function upgrade_project {
  # Upgrade the project

  local project_id="$1" # Ex: project_id=6a35cb96-2227-419d-bf64-9c8e91c69410
  echo "-== Starting upgrade process for $PROJECT_NAME project... ==-"
  echo "Docker Project ID: $project_id"

  # Get project images
  local project_images
  project_images=$(get_project_images "$project_id")
  local return_code=$?; [ $return_code -ne 0 ] && { return $return_code; }

  # Get list of upgradable images
  local upgradable_images
  upgradable_images=$(get_upgradable_images)
  local return_code=$?; [ $return_code -ne 0 ] && { return $return_code; }

  # Build arry of images that are ready to be upgraded
  local upgrade_image_list
  while IFS= read -r image; do
    if [[ "$upgradable_images" == *"$image"* ]]; then
      upgrade_image_list+="${image}$'\n'"
    fi    
  done <<< "$project_images"
  if [ -z "$upgrade_image_list" ]; then
    echo_ansi "Warn: Project contained no upgradeable images"
    return 1
  fi
  printf "Upgradable Images: %s" "$upgrade_image_list" | tr "\n" ","; echo ""

  # Upgrade all upgradable images in the project
  upgrade_images "$upgrade_image_list"
  local return_code=$?; [ $return_code -ne 0 ] && { return $return_code; }

  # Rebuild the project to apply the image upgrades
  build_project "$project_id"
  local return_code=$?; [ $return_code -ne 0 ] && { return $return_code; }

  if [ -z "$NOPRUNE" ]; then
    # Remove old images that are no longer used by any containers
    prune_images
    local return_code=$?; [ $return_code -ne 0 ] && { return $return_code; }
  fi

  echo "-== Upgrade process completed for $PROJECT_NAME project! ==-"
}
function get_upgradable_images {
  # Get a list of upgradable images in the project

  local response
  response=$(call_api "SYNO.Docker.Image" "list" "limit=-1" "offset=0" "show_dsm=false")
  local return_code=$?
  [ $return_code -ne 0 ] && { echo_ansi "Error: Failed to retrieve upgradable image list from API." >&2; return $return_code; }

  local upgradable_images
  upgradable_images=$(echo "$response" | jq -crM '.data.images | map(select(.upgradable))[].repository')

  if [ -z "$upgradable_images" ]; then
    echo_ansi "Warn: No upgradable images found." >&2
    return 1
  fi

  echo "$upgradable_images"
}
function upgrade_images {
  # Upgrade upgradable images

  local upgradable_images="$1" # Ex: "linuxserver/sonarr\nlinuxserver/radarr\nlinuxserver/lidarr"

  local exit_code=0
  # Use a while loop with IFS set to an empty string and read -r to process each line exactly as is
  # NOTE: Double quotes around repository name avoids NOT JSON error
  while IFS= read -r image; do
    local response
    response=$(call_api "SYNO.Docker.Image" "upgrade_start" "repository=\"$image\"")
    local return_code=$?
    [ $return_code -ne 0 ] && { echo_ansi "Error: Failed to retrieve task ID from API for $image." >&2; continue; }

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
      echo_ansi "Error: Upgrade failed for $image with status $upgrade_finished" >&2
      exit_code=2
    fi
  done <<< "$upgradable_images"
  return $exit_code
}
function check_upgrade_status {
  # Check the upgrade status of a given task ID

  local task_id="$1" # ID returned from upgrade_start API call

  local response
  response=$(call_api "SYNO.Docker.Image" "upgrade_status" "task_id=\"$task_id\"")
  local return_code=$?
  [ $return_code -ne 0 ] && { echo_ansi "Error: Failed to retrieve upgrade status from API for $task_id." >&2; return $return_code; }

  local upgrade_finished
  upgrade_finished=$(echo "$response" | jq -crM ".data.finished")
  echo "$upgrade_finished"
}
function prune_images {
  # Clean up unused images

  local response
  response=$(call_api "SYNO.Docker.Image" "prune")
  local return_code=$?
  [ $return_code -ne 0 ] && { echo_ansi "Error: Failed to prune images via API." >&2; return $return_code; }

  local success
  success=$(echo "$response" | jq -crM '.success')
  if [ "$success" != "true" ]; then
    echo_ansi "Error: Prune image failed" >&2
    return 1
  fi

  local message
  message=$(echo "$response" | jq -crM '(.data.ImagesDeleted|length) as $count | (.data.SpaceReclaimed | tostring | gsub("(?<=\\d)(?=(\\d{3})+(?!\\d))"; ",")) as $space | "\($count) images deleted saving \($space) bytes."')
  echo "$message"
}

# Do not execute if this script is being sourced from a test script
if [[ ! "${BASH_SOURCE[1]}" =~ test_.*\.sh$ ]]; then
  main "$@"
fi
