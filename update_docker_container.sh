#!/bin/bash

# === CONFIGURATION ===
LOG_FILE="log.txt"
DOCKERFILE_LOG="dockerupdatelog.txt"
NETWORK_LOG="network_map.txt"
ROLLBACK_DIR="rollback_configs"
SUMMARY_LOG="summary.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
mkdir -p "$ROLLBACK_DIR"

# === REQUIREMENTS CHECK ===
command -v docker >/dev/null || { echo "Docker is not installed."; exit 1; }
command -v jq >/dev/null || { echo "jq is required. Install with: sudo apt install jq"; exit 1; }

# === UTILITIES ===
log_summary() {
  echo "[$TIMESTAMP] $1" | tee -a "$SUMMARY_LOG"
}

export_config() {
  container_id="$1"
  docker inspect "$container_id" > "$ROLLBACK_DIR/$container_id.json"
}

is_compose_container() {
  docker inspect "$1" | jq -e '.[0].Config.Labels["com.docker.compose.project"]' >/dev/null 2>&1
}

is_swarm_service() {
  docker inspect --format '{{ index .Config.Labels "com.docker.swarm.service.name" }}' "$1" 2>/dev/null
}

# === MENU ===
echo "Available containers:"
docker ps --format "table {{.ID}}\t{{.Image}}\t{{.Names}}"
echo

echo "Select Mode:"
echo "1) Safe Update (Swarm-aware)"
echo "2) Dockerfile Update"
echo "3) Interactive Mode"
echo "4) Network Mapping"
echo "5) Rollback Support"
echo "6) Compose Awareness Check"
echo "7) Show Update Summary"
echo "8) Security Scan (basic)"
echo "9) Export Container Configs"
read -rp "Enter your choice [1-9]: " mode

# === MODE HANDLERS ===

if [[ "$mode" == "1" ]]; then
  echo "Safe update for Swarm containers..."
  docker service ls --format '{{.Name}}' | while read svc; do
    image=$(docker service inspect --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' "$svc")
    log_summary "Pulling latest for $image"
    docker pull "$image"
    log_summary "Updating service $svc"
    docker service update --image "$image" "$svc"
  done
  exit 0
fi

if [[ "$mode" == "2" ]]; then
  docker ps -q | while read cid; do
    image=$(docker inspect --format '{{.Config.Image}}' "$cid")
    name=$(docker inspect --format '{{.Name}}' "$cid" | sed 's/^\///')
    if [[ "$image" == "<none>" || "$image" != *"/"* ]]; then
      echo "Dockerfile container: $name"
      read -rp "Rebuild? [y/N]: " choice
      if [[ "$choice" =~ ^[Yy]$ ]]; then
        read -rp "Enter Dockerfile path: " path
        export_config "$cid"
        docker build -t "$name" "$path" && docker stop "$cid" && docker rm "$cid"
        docker run -d --name "$name" "$name"
        log_summary "Rebuilt Dockerfile container: $name"
      fi
    fi
  done
  exit 0
fi

if [[ "$mode" == "3" ]]; then
  docker ps --format "table {{.ID}}\t{{.Image}}\t{{.Names}}"
  read -rp "Enter container ID or name: " cid
  export_config "$cid"
  docker inspect "$cid" | jq '.[0] | {Name: .Name, Image: .Config.Image, Ports: .HostConfig.PortBindings, Env: .Config.Env, Volumes: .Mounts}'
  exit 0
fi

if [[ "$mode" == "4" ]]; then
  for net in $(docker network ls --format '{{.Name}}'); do
    echo "Network: $net" | tee -a "$NETWORK_LOG"
    docker network inspect "$net" | jq -r '.[0].Containers[]? | "  - Container: \(.Name) | IPv4: \(.IPv4Address)"' | tee -a "$NETWORK_LOG"
  done
  exit 0
fi

if [[ "$mode" == "5" ]]; then
  echo "Saved rollback configs are in $ROLLBACK_DIR"
  ls "$ROLLBACK_DIR"
  exit 0
fi

if [[ "$mode" == "6" ]]; then
  echo "Checking for Compose-managed containers..."
  docker ps -q | while read cid; do
    if is_compose_container "$cid"; then
      name=$(docker inspect --format '{{.Name}}' "$cid")
      echo "Compose-managed: ${name#/}"
    fi
  done
  exit 0
fi

if [[ "$mode" == "7" ]]; then
  echo "--- Update Summary Log ---"
  cat "$SUMMARY_LOG"
  exit 0
fi

if [[ "$mode" == "8" ]]; then
  echo "Security scan simulation (basic exposed ports check):"
  docker ps --format '{{.ID}} {{.Names}}' | while read cid name; do
    echo "$name:"
    docker port "$cid"
  done
  exit 0
fi

if [[ "$mode" == "9" ]]; then
  echo "Exporting configs..."
  docker ps -q | while read cid; do
    export_config "$cid"
    echo "Exported: $cid"
  done
  exit 0
fi
