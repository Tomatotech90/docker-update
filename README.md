
# Docker Container Update Script

## Overview

This Bash script is a comprehensive tool for managing and safely updating Docker containers and services. It supports Docker Swarm, Dockerfile-built containers, interactive updates, and network inspection, with built-in logging, rollback support, and Compose detection.

The script provides a user-friendly terminal menu and ensures all updates are performed using the safest and most Docker-compliant methods.

---

## Requirements

- **Docker**: Must be installed and running.
- **jq**: JSON parser used for inspecting container configurations.

Install jq (if missing):

```bash
sudo apt install jq
```

---

## Features

- **Safe Swarm updates** using `docker service update --image`
- **Rollback support** by saving `docker inspect` JSON before changes
- **Compose awareness**: detects and labels Docker Compose containers
- **Dockerfile container updates** via rebuilds
- **Interactive configuration inspection**
- **Network mapping and visualization**
- **Security scan** (exposed ports summary)
- **Full update summary logging**
- **Export of container configurations**

---

## Usage

Make the script executable:

```bash
chmod +x update_docker_container.sh
```

Run it:

```bash
./update_docker_container.sh
```

---

## Menu Options

### 1) Safe Update (Swarm-aware)

- Pulls the latest image for each Swarm service.
- Updates each service with `docker service update --image`.
- Logs summary to `summary.log`.

### 2) Dockerfile Update

- Detects locally built images (`<none>` or no repository prefix).
- Asks for Dockerfile path and rebuilds image.
- Restarts container with same name.
- Logs changes to `dockerupdatelog.txt`.

### 3) Interactive Mode

- Shows container configuration: image, ports, env, mounts.
- Allows user to inspect or modify before manual update.

### 4) Network Mapping

- Lists all Docker networks.
- Shows connected containers and their IPs.
- Outputs to `network_map.txt`.

### 5) Rollback Support

- Lists saved container configurations.
- Allows manual restore from `rollback_configs/` directory.

### 6) Compose Awareness Check

- Scans running containers for Compose labels.
- Marks Compose-managed containers.

### 7) Show Update Summary

- Prints contents of `summary.log` (updates performed).

### 8) Security Scan (basic)

- Lists exposed ports for each container using `docker port`.

### 9) Export Container Configs

- Saves `docker inspect` output for each container to `rollback_configs/`.

---

## Logging and Output Files

- `log.txt`: Logs updates to standard containers.
- `dockerupdatelog.txt`: Logs Dockerfile image updates.
- `summary.log`: Global summary of all updates.
- `network_map.txt`: Container network connection overview.
- `rollback_configs/`: Stores full `docker inspect` JSONs for rollback.

---

## Notes

- Swarm services are updated in-place (no deletion or downtime).
- Standalone container updates are not destructive if rollback is used.
- Docker Compose containers are detected but not updated directly — use `docker-compose pull && up -d` manually.

---

## Future Enhancements

- Automated rollback execution
- Image digest/version comparison
- Email or webhook alerts
- YAML export support
- Automated scheduling via cron

---

## License

MIT License. Modify and use freely with proper safety precautions.
