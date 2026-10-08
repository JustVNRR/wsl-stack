# Docker

[← Back to the README](../../../../../README.md#makefile-gmake)

## Targets

| Target | Action | Confirmation |
| :--- | :--- | :--- |
| `docker_build_local` | Build the image locally (`:dev` tag) | — |
| `docker_run_local` | Run the local container on port 8080 | — |

## Variables

| Variable | Required by | Example |
| :--- | :--- | :--- |
| `PACKAGE_NAME` | `docker_build_local` | `my-package` |
| `DOCKER_BASE_IMAGE` | `docker_build_local` | `python:3.10.6-slim` |
| `DOCKER_LOCAL_IMAGE` | both | `my-api` |
| `GAR_IMAGE` | the GCP build target | `my-api` |
