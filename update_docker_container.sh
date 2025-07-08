#!/bin/bash

# === CONFIGURATION ===
LOG_FILE="log.txt"
DOCKERFILE_LOG="dockerupdatelog.txt"
NETWORK_LOG="network_map.txt"
ROLLBACK_DIR="rollback_configs"
SUMMARY_LOG="summary.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
mkdir -p "$ROLLBACK_DIR"

# === COLORS ===
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# === REQUIREMENTS CHECK ===
command -v docker >/dev/null || { echo -e "${RED}Docker is not installed.${NC}"; exit 1; }
command -v jq >/dev/null || { echo -e "${RED}jq is required. Install with: sudo apt install jq${NC}"; exit 1; }
command -v docker-compose >/dev/null || { echo -e "${RED}docker-compose is required for Compose updates. Install it if needed.${NC}"; }

# === UTILITIES ===
log_summary() {
  echo "[$TIMESTAMP] $1" | tee -a "$SUMMARY_LOG"
}

export_config() {
  local container_id="$1"
  docker inspect "$container_id" > "$ROLLBACK_DIR/$container_id.json" 2>/dev/null
}

is_compose_container() {
  docker inspect "$1" | jq -e '.[0].Config.Labels["com.docker.compose.project"]' >/dev/null 2>&1
}

is_swarm_service() {
  docker inspect --format '{{ index .Config.Labels "com.docker.swarm.service.name" }}' "$1" 2>/dev/null
}

is_dockerfile_container() {
  local image=$(docker inspect --format '{{.Config.Image}}' "$1" 2>/dev/null)
  [[ "$image" == "<none>" || "$image" != *"/"* ]]
}

is_updatable() {
  local container_id="$1"
  local image=$(docker inspect --format '{{.Config.Image}}' "$container_id" 2>/dev/null)
  local service_name
  service_name=$(is_swarm_service "$container_id")

  if is_compose_container "$container_id"; then
    echo "N/A" # Compose containers are managed via docker-compose
  elif [[ -n "$service_name" ]]; then
    image=$(docker service inspect --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' "$service_name" 2>/dev/null)
    if docker pull "$image" >/dev/null 2>&1; then
      echo "Yes"
    else
      echo "No"
    fi
  else
    if [[ "$image" != "<none>" && "$image" == *"/"* ]]; then
      if docker pull "$image" >/dev/null 2>&1; then
        echo "Yes"
      else
        echo "No"
      fi
    else
      echo "No"
    fi
  fi
}

# === DISPLAY CONTAINERS ===
display_containers() {
  local filter="$1"
  echo -e "${CYAN}Running Containers:${NC}"
  printf "%-12s %-30s %-20s %-15s %-10s\n" "ID" "Image" "Name" "Type" "Updatable"
  echo "---------------------------------------------------------------"
  docker ps --format '{{.ID}} {{.Image}} {{.Names}}' | while read -r cid image name; do
    if is_compose_container "$cid"; then
      type="Compose"
    elif is_swarm_service "$cid"; then
      type="Swarm"
    elif is_dockerfile_container "$cid"; then
      type="Dockerfile"
    else
      type="Standalone"
    fi
    updatable=$(is_updatable "$cid")
    if [[ "$filter" == "updatable" && "$updatable" != "Yes" ]]; then
      continue
    fi
    if [[ "$updatable" == "Yes" ]]; then
      updatable_display="\e[32mYes\e[0m"
    elif [[ "$updatable" == "No" ]]; then
      updatable_display="\e[31mNo\e[0m"
    else
      updatable_display="$updatable"
    fi
    printf "%-12s %-30s %-20s %-15s %b\n" "$cid" "$image" "$name" "$type" "$updatable_display"
  done
  echo
}

# === MENU ===
show_menu() {
  echo -e "${CYAN}Select Mode:${NC}"
  echo "1) Safe Update (Standalone and Swarm containers)"
  echo "2) Dockerfile Update"
  echo "3) Interactive Mode"
  echo "4) Network Mapping"
  echo "5) Rollback Support"
  echo "6) Compose Awareness Check"
  echo "7) Show Update Summary"
  echo "8) Security Scan (basic)"
  echo "9) Export Container Configs"
  echo "10) Container Health Check"
  echo "11) Update Compose Containers"
  echo "12) Show Only Updatable Containers"
  echo "0) Exit"
  read -rp "Enter your choice [0-12]: " mode
}

# === MODE HANDLERS ===
handle_safe_update() {
  echo "Update standalone and Swarm containers:"
  echo "1) Automatic Update (Standalone and Swarm)"
  echo "2) Manual Update (Standalone only)"
  read -rp "Choose update method [1-2]: " update_mode
  local standalone_found=false
  if [[ "$update_mode" == "1" ]]; then
    docker ps --format '{{.ID}} {{.Image}} {{.Names}}' | while read -r cid image name; do
      if is_compose_container "$cid" || is_dockerfile_container "$cid"; then
        continue
      fi
      if is_swarm_service "$cid"; then
        service_name=$(is_swarm_service "$cid")
        if [[ $(is_updatable "$cid") == "Yes" ]]; then
          echo -e "${CYAN}Updating Swarm service: $service_name${NC}"
          log_summary "Pulling latest for $image (Swarm service: $service_name)"
          docker pull "$image" && docker service update --image "$image" "$service_name"
          log_summary "Updated Swarm service: $service_name"
        else
          echo "No update available for Swarm service: $service_name"
        fi
      else
        standalone_found=true
        if [[ $(is_updatable "$cid") == "Yes" ]]; then
          echo -e "${CYAN}Updating standalone container: $name${NC}"
          export_config "$cid"
          log_summary "Pulling latest for $image"
          docker pull "$image" && docker stop "$cid" && docker rm "$cid"
          docker run -d --name "$name" "$image"
          log_summary "Updated standalone container: $name"
        else
          echo "No update available for standalone container: $name"
        fi
      fi
    done
  elif [[ "$update_mode" == "2" ]]; then
    docker ps --format '{{.ID}} {{.Image}} {{.Names}}' | while read -r cid image name; do
      if is_compose_container "$cid" || is_dockerfile_container "$cid" || is_swarm_service "$cid"; then
        continue
      fi
      standalone_found=true
      if [[ $(is_updatable "$cid") == "Yes" ]]; then
        echo "Container: $name (Image: $image)"
        read -rp "Update? [y/N]: " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
          echo -e "${CYAN}Updating standalone container: $name${NC}"
          export_config "$cid"
          log_summary "Pulling latest for $image"
          docker pull "$image" && docker stop "$cid" && docker rm "$cid"
          docker run -d --name "$name" "$image"
          log_summary "Updated standalone container: $name"
        else
          echo "Skipped update for standalone container: $name"
        fi
      else
        echo "No update available for standalone container: $name"
      fi
    done
    if ! $standalone_found; then
      echo -e "${RED}No Standalone containers available for manual update.${NC}"
    fi
  else
    echo -e "${RED}Invalid choice. Please select [1-2].${NC}"
  fi
  read -rp "Press Enter to continue..."
}

handle_dockerfile_update() {
  local found=false
  docker ps --format '{{.ID}} {{.Image}} {{.Names}}' | while read -r cid image name; do
    if is_dockerfile_container "$cid"; then
      found=true
      echo "Dockerfile container: $name"
      read -rp "Rebuild? [y/N]: " choice
      if [[ "$choice" =~ ^[Yy]$ ]]; then
        read -rp "Enter Dockerfile path: " path
        if [[ -f "$path" ]]; then
          export_config "$cid"
          echo -e "${CYAN}Rebuilding Dockerfile container: $name${NC}"
          docker build -t "$name" "$path" && docker stop "$cid" && docker rm "$cid"
          docker run -d --name "$name" "$name"
          log_summary "Rebuilt Dockerfile container: $name"
        else
          echo -e "${RED}Dockerfile not found at $path${NC}"
        fi
      else
        echo "Skipped rebuild for Dockerfile container: $name"
      fi
    fi
  done
  if ! $found; then
    echo -e "${RED}No Dockerfile containers found.${NC}"
  fi
  read -rp "Press Enter to continue..."
}

handle_interactive_mode() {
  if docker ps -q | read -r cid; then
    docker ps --format "table {{.ID}}\t{{.Image}}\t{{.Names}}"
    read -rp "Enter container ID or name: " cid
    if docker inspect "$cid" >/dev/null 2>&1; then
      export_config "$cid"
      docker inspect "$cid" | jq '.[0] | {Name: .Name, Image: .Config.Image, Ports: .HostConfig.PortBindings, Env: .Config.Env, Volumes: .Mounts}'
    else
      echo -e "${RED}Invalid container ID or name.${NC}"
    fi
  else
    echo -e "${RED}No running containers found.${NC}"
  fi
  read -rp "Press Enter to continue..."
}

handle_network_mapping() {
  if docker network ls --format '{{.Name}}' | read -r net; then
    for net in $(docker network ls --format '{{.Name}}'); do
      echo "Network: $net" | tee -a "$NETWORK_LOG"
      docker network inspect "$net" | jq -r '.[0].Containers[]? | "  - Container: \(.Name) | IPv4: \(.IPv4Address)"' | tee -a "$NETWORK_LOG"
    done
  else
    echo -e "${RED}No networks found.${NC}"
  fi
  read -rp "Press Enter to continue..."
}

handle_rollback_support() {
  if ls "$ROLLBACK_DIR"/*.json >/dev/null 2>&1; then
    echo "Saved rollback configs are in $ROLLBACK_DIR"
    ls "$ROLLBACK_DIR"
  else
    echo -e "${RED}No rollback configs found in $ROLLBACK_DIR.${NC}"
  fi
  read -rp "Press Enter to continue..."
}

handle_compose_check() {
  local found=false
  docker ps --format '{{.ID}} {{.Names}}' | while read -r cid name; do
    if is_compose_container "$cid"; then
      found=true
      echo "Compose-managed: ${name#/}"
    fi
  done
  if ! $found; then
    echo -e "${RED}No Compose-managed containers found.${NC}"
  fi
  read -rp "Press Enter to continue..."
}

handle_summary() {
  if [[ -f "$SUMMARY_LOG" ]]; then
    echo "--- Update Summary Log ---"
    cat "$SUMMARY_LOG"
  else
    echo -e "${RED}No summary log found.${NC}"
  fi
  read -rp "Press Enter to continue..."
}

handle_security_scan() {
  local found=false
  docker ps --format '{{.ID}} {{.Names}}' | while read -r cid name; do
    found=true
    echo "$name:"
    docker port "$cid"
  done
  if ! $found; then
    echo -e "${RED}No running containers found for security scan.${NC}"
  fi
  read -rp "Press Enter to continue..."
}

handle_health_check() {
  local found=false
  echo "Container Health Check:"
  printf "%-12s %-20s %-10s\n" "ID" "Name" "Health"
  echo "------------------------------------"
  docker ps --format '{{.ID}} {{.Names}} {{.Status}}' | while read -r cid name status; do
    found=true
    if [[ "$status" =~ "healthy" ]]; then
      health="\e[32mHealthy\e[0m"
    elif [[ "$status" =~ "unhealthy" ]]; then
      health="\e[31mUnhealthy\e[0m"
    else
      health="N/A"
    fi
    printf "%-12s %-20s %b\n" "$cid" "$name" "$health"
  done
  if ! $found; then
    echo -e "${RED}No running containers found.${NC}"
  fi
  read -rp "Press Enter to continue..."
}

handle_export_configs() {
  local found=false
  echo "Exporting configs..."
  docker ps -q | while read -r cid; do
    found=true
    export_config "$cid"
    echo "Exported: $cid"
  done
  if ! $found; then
    echo -e "${RED}No running containers found to export.${NC}"
  fi
  read -rp "Press Enter to continue..."
}

handle_compose_update() {
  local found=false
  echo "Updating Compose-managed containers..."
  docker ps --format '{{.ID}} {{.Names}}' | while read -r cid name; do
    if is_compose_container "$cid"; then
      found=true
      echo -e "${CYAN}Compose container: ${name#/}${NC}"
      project=$(docker inspect "$cid" | jq -r '.[0].Config.Labels["com.docker.compose.project"]')
      compose_file=$(find / -name "docker-compose.yml" -exec grep -l "container_name:.*${name#/}" {} \; 2>/dev/null | head -n 1)
      if [[ -n "$compose_file" ]]; then
        echo "Found docker-compose file: $compose_file"
      else
        echo -e "${RED}No docker-compose file found for ${name#/}.${NC}"
        read -rp "Enter docker-compose file path for ${name#/} (or press Enter to skip): " compose_file
        if [[ ! -f "$compose_file" ]]; then
          echo "Skipped update for ${name#/}: Invalid or no file provided."
          continue
        fi
      fi
      read -rp "Update using docker-compose? [y/N]: " choice
      if [[ "$choice" =~ ^[Yy]$ ]]; then
        export_config "$cid"
        echo -e "${CYAN}Updating Compose container: ${name#/}${NC}"
        log_summary "Updating Compose container: ${name#/} using $compose_file"
        (cd "$(dirname "$compose_file")" && docker-compose -f "$(basename "$compose_file")" up -d)
        log_summary "Updated Compose container: ${name#/}"
      else
        echo "Skipped update for Compose container: ${name#/}"
      fi
    fi
  done
  if ! $found; then
    echo -e "${RED}No Compose-managed containers found.${NC}"
  fi
  read -rp "Press Enter to continue..."
}

handle_updatable_filter() {
  local found=false
  echo -e "${CYAN}Updatable Containers:${NC}"
  printf "%-12s %-30s %-20s %-15s %-10s\n" "ID" "Image" "Name" "Type" "Updatable"
  echo "---------------------------------------------------------------"
  docker ps --format '{{.ID}} {{.Image}} {{.Names}}' | while read -r cid image name; do
    if [[ $(is_updatable "$cid") == "Yes" ]]; then
      found=true
      if is_compose_container "$cid"; then
        type="Compose"
      elif is_swarm_service "$cid"; then
        type="Swarm"
      elif is_dockerfile_container "$cid"; then
        type="Dockerfile"
      else
        type="Standalone"
      fi
      printf "%-12s %-30s %-20s %-15s %b\n" "$cid" "$image" "$name" "$type" "\e[32mYes\e[0m"
    fi
  done
  if ! $found; then
    echo -e "${RED}No updatable containers found.${NC}"
  fi
  read -rp "Press Enter to continue..."
}

# === MAIN LOOP ===
while true; do
  display_containers
  show_menu
  case "$mode" in
    1)
      handle_safe_update
      ;;
    2)
      handle_dockerfile_update
      ;;
    3)
      handle_interactive_mode
      ;;
    4)
      handle_network_mapping
      ;;
    5)
      handle_rollback_support
      ;;
    6)
      handle_compose_check
      ;;
    7)
      handle_summary
      ;;
    8)
      handle_security_scan
      ;;
    9)
      handle_export_configs
      ;;
    10)
      handle_health_check
      ;;
    11)
      handle_compose_update
      ;;
    12)
      handle_updatable_filter
      ;;
    0)
      echo -e "${CYAN}Exiting...${NC}"
      exit 0
      ;;
    *)
      echo -e "${RED}Invalid choice. Please select [0-12].${NC}"
      read -rp "Press Enter to continue..."
      ;;
  esac
  echo -e "\n\n"
done
