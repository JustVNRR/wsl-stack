# ======================
# 🐳 DOCKER CHEATSHEET
# requires: docker
# ======================
# The docker commands a project is built, run and cleaned with. Offered while
# docker answers - it comes from Docker Desktop, not from this pack.

# --- 1. IMAGE MANAGEMENT (Build Blueprints) ---
docker images                                # List all images downloaded or built locally
docker pull <IMAGE_NAME>                     # Pull an image from Docker Hub
docker build -t <IMAGE_NAME>:<TAG> .         # Build an image from the Dockerfile in the current directory
docker rmi <IMAGE_ID>                        # Remove a specific image
docker image prune                           # Remove dangling images (untagged intermediate layers)

# --- 2. CONTAINER MANAGEMENT (Running Instances) ---
docker ps                                    # List all currently running containers
docker ps -a                                 # List ALL containers (including stopped or exited)
docker start <CONTAINER_NAME>                # Start a stopped container
docker stop <CONTAINER_NAME>                 # Gracefully stop a running container
docker restart <CONTAINER_NAME>              # Restart a container
docker rm <CONTAINER_NAME>                   # Remove a stopped container
docker rm -f <CONTAINER_NAME>                # ⚠️ Force-stop and remove a running container

# --- 3. RUNNING CONTAINERS (Run Command) ---
# Run in detached mode (-d) with a custom name and port binding (Host:Container)
docker run -d --name <CONTAINER_NAME> -p <HOST_PORT>:<CONTAINER_PORT> <IMAGE_NAME>

# Run a disposable container (--rm) in interactive mode (-it)
docker run --rm -it <IMAGE_NAME> /bin/bash

# --- 4. INTERACTION & DEBUGGING (Troubleshooting) ---
docker logs <CONTAINER_NAME>                 # Print stdout/stderr logs from container
docker logs -f <CONTAINER_NAME>              # Stream logs in real time (equivalent to 'tail -f')
docker exec -it <CONTAINER_NAME> /bin/bash   # 🛡️ Open an interactive bash shell inside a running container (use 'sh' for Alpine)
docker top <CONTAINER_NAME>                  # Display running processes inside the container
docker inspect <CONTAINER_NAME>              # Display low-level configuration details (IP, mounts, env vars)

# --- 5. DOCKER COMPOSE (Multi-Container Orchestration) ---
docker compose up -d                         # Build and start all services defined in docker-compose.yml in detached mode
docker compose down                          # Stop and remove containers, networks, and volumes defined in compose
docker compose logs -f                       # Stream aggregated logs across all compose services
docker compose build                         # Rebuild or build image definitions specified in compose file

# --- 6. SYSTEM CLEANUP (Disk Space Reclamation) ---
docker system prune                          # Remove stopped containers, unused networks, and dangling images
docker system prune -a --volumes             # ⚠️ Nuclear purge: remove all stopped containers, unused images, and anonymous volumes
