# Docker Container Update Script


This Bash script automates updating a Docker container to its latest image version while preserving its configuration. It supports two modes:

- **Default Mode**: Automatically extracts the container's settings (image, ports, volumes, restart policy, environment variables) using `docker inspect` and applies them to the updated container.
- **Interactive Mode**: Prompts the user to manually specify the container's settings, allowing customization during the update.

The script displays running containers, validates inputs, and ensures data persistence by reusing volumes, making it suitable for updating containers like Portainer, MySQL, or others.

## Prerequisites

- **Docker**: Installed and running on the system.
- **jq**: Required for parsing `docker inspect` output in Default Mode. Install it:
  - Ubuntu/Debian: `sudo apt-get install jq`
  - macOS: `brew install jq`
  - Other systems: Refer to [jq documentation](https://stedolan.github.io/jq/).

## Installation

1. Save the script as `update_docker_container.sh`.
2. Make it executable:
   ```bash
   chmod +x update_docker_container.sh
   ```

## Usage

Run the script:

```bash
./update_docker_container.sh
```

### Steps:

- The script displays running containers via `docker ps`.
- Enter the name or ID of the container to update.
- Choose a mode:
  - 1 (Default Mode): Extracts settings from `docker inspect`.
  - 2 (Interactive Mode): Prompts for manual input of image, ports, volumes, restart policy, and environment variables.
- Review the displayed settings (auto-extracted or user-entered).
- Please confirm the procedure for stopping, removing, and recreating the container.
- Check the updated container's status with `docker ps` and access it as needed.

## Features

- Displays running containers for easy selection.
- Default Mode auto-extracts configuration (image, ports, volumes, restart policy, environment variables).
- Interactive Mode allows manual configuration input.
- Validates the presence of Docker and jq, verifies container existence, and confirms command execution.
- Warns about missing volumes to prevent data loss.
- Supports any container with a valid image tag (defaults to 'latest' or an existing tag).

## Notes

- **Data Persistence**: Ensures volumes (such as `portainer_data`) are reused to preserve data. Warns if no volumes are detected.
- **Port Conflicts**: Fails if ports are in use. Check with:
  ```bash
  netstat -tuln | grep <port>
  sudo lsof -i:<port>
  ```
- **Docker Compose**: For Compose-managed containers, update the `docker-compose.yml` and run `docker-compose pull && docker-compose up -d` instead.
- **Limitations**: Handles standard settings. Complex configurations (such as custom networks) may require script modifications or the use of Interactive Mode.

## Troubleshooting

- **Port Conflicts**: Resolve by freeing the port or selecting an alternative one.
- **Missing jq**: Install jq if Default Mode fails.
- **Data Loss**: Ensure volumes are specified to prevent data loss.
- **Errors**: Check error messages and verify container status with `docker ps -a`.
