#!/bin/bash

# Script to update a Docker container with default (auto-extracted) or interactive (user-input) modes

# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed or not running."
    exit 1
fi

# Check if jq is installed (needed for default mode)
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install it ('sudo apt-get install jq' on Ubuntu)."
    exit 1
fi

# Display running containers
echo "Running containers:"
docker ps
echo ""

# Prompt user for container name or ID
read -p "Enter the name or ID of the container to update: " container_name

# Verify container exists
if ! docker inspect "$container_name" &> /dev/null; then
    echo "Error: Container '$container_name' does not exist."
    exit 1
fi

# Prompt for mode selection
echo "Choose update mode:"
echo "1) Default mode (auto-extract settings from docker inspect)"
echo "2) Interactive mode (manually input settings)"
read -p "Enter 1 or 2 (default is 1): " mode
mode=${mode:-1} # Default to 1 if no input

if [ "$mode" == "1" ]; then
    # Default mode: Extract settings from docker inspect
    container_info=$(docker inspect "$container_name")
    
    # Extract image
    image=$(echo "$container_info" | jq -r '.[0].Config.Image')
    if [ -z "$image" ]; then
        echo "Error: Could not retrieve image for container '$container_name'."
        exit 1
    fi
    if [[ "$image" != *:latest ]]; then
        echo "Warning: Image '$image' does not use the :latest tag. Proceeding with the same tag."
    }

    # Extract port bindings
    ports=$(echo "$container_info" | jq -r '.[0].HostConfig.PortBindings | to_entries[] | "-p \(.key | split("/")[0]):\(.value[0].HostPort)"' | tr '\n' ' ')
    if [ -z "$ports" ]; then
        echo "No port bindings found. Proceeding without ports."
        ports=""
    fi

    # Extract volume mounts
    volumes=$(echo "$container_info" | jq -r '.[0].HostConfig.Binds[]' | tr '\n' ' ' | sed 's/ / -v /g')
    if [ -z "$volumes" ]; then
        echo "Warning: No volume mounts found. Data may be lost if not stored persistently."
        read -p "Continue without volumes? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Aborted by user."
            exit 1
        fi
        volumes=""
    else
        volumes="-v $volumes"
    fi

    # Extract restart policy
    restart_policy=$(echo "$container_info" | jq -r '.[0].HostConfig.RestartPolicy.Name')
    if [ "$restart_policy" != "no" ] && [ -n "$restart_policy" ]; then
        restart_flag="--restart=$restart_policy"
    else
        restart_flag=""
    fi

    # Extract environment variables
    env_vars=$(echo "$container_info" | jq -r '.[0].Config.Env[]' | tr '\n' ' ' | sed 's/ / -e /g')
    if [ -n "$env_vars" ]; then
        env_vars="-e $env_vars"
    else
        env_vars=""
    fi

    # Display extracted settings
    echo "Extracted settings for '$container_name':"
    echo "Image: $image"
    echo "Ports: $ports"
    echo "Volumes: $volumes"
    echo "Restart Policy: $restart_flag"
    echo "Environment Variables: $env_vars"
else
    # Interactive mode: Prompt for settings
    read -p "Enter the image name (portainer/portainer-ce:latest): " image
    if [ -z "$image" ]; then
        echo "Error: Image name cannot be empty."
        exit 1
    fi

    read -p "Enter port mappings (9000:9000 8000:8000, or press Enter for none): " ports_input
    if [ -n "$ports_input" ]; then
        ports=$(echo "$ports_input" | sed 's/ / -p /g' | sed 's/^/-p /')
    else
        ports=""
    fi

    read -p "Enter volume mounts (/var/run/docker.sock:/var/run/docker.sock portainer_data:/data, or press Enter for none): " volumes_input
    if [ -n "$volumes_input" ]; then
        volumes=$(echo "$volumes_input" | sed 's/ / -v /g' | sed 's/^/-v /')
        echo "Warning: Ensure volumes exist to avoid data loss."
    else
        echo "Warning: No volumes specified. Data may be lost if not stored persistently."
        read -p "Continue without volumes? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Aborted by user."
            exit 1
        fi
        volumes=""
    fi

    read -p "Enter restart policy (always, unless-stopped, or press Enter for none): " restart_policy
    if [ -n "$restart_policy" ]; then
        restart_flag="--restart=$restart_policy"
    else
        restart_flag=""
    fi

    read -p "Enter environment variables ( KEY1=value1 KEY2=value2, or press Enter for none): " env_vars_input
    if [ -n "$env_vars_input" ]; then
        env_vars=$(echo "$env_vars_input" | sed 's/ / -e /g' | sed 's/^/-e /')
    else
        env_vars=""
    fi

    # Display user-entered settings
    echo "User-entered settings for '$container_name':"
    echo "Image: $image"
    echo "Ports: $ports"
    echo "Volumes: $volumes"
    echo "Restart Policy: $restart_flag"
    echo "Environment Variables: $env_vars"
fi

# Confirm with user
read -p "Proceed with update? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted by user."
    exit 1
fi

# Stop and remove the container
echo "Stopping and removing container '$container_name'..."
docker stop "$container_name" &> /dev/null || { echo "Failed to stop container."; exit 1; }
docker rm "$container_name" &> /dev/null || { echo "Failed to remove container."; exit 1; }

# Pull the image
echo "Pulling image '$image'..."
docker pull "$image" || { echo "Failed to pull image."; exit 1; }

# Recreate the container
echo "Recreating container '$container_name'..."
run_cmd="docker run -d --name \"$container_name\" $restart_flag $ports $volumes $env_vars \"$image\""
eval $run_cmd || { echo "Failed to recreate container."; exit 1; }

echo "Container '$container_name' updated successfully!"
echo "Check the container status with 'docker ps' and access it as needed."
