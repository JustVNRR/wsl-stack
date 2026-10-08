# Artifact Registry

[← Back to the README](../../../../../README.md#makefile-gmake)

## Targets

| Target | Action | Confirmation |
|---|---|---|
| `artifact_registry_create` | Create the Docker repository in Artifact Registry | ⚠️ |
| `artifact_registry_role` | Grant yourself Artifact Registry Writer (IAM) | ⚠️ |
| `artifact_registry_auth` | Configure Docker to authenticate with GCP | — |
| `artifact_registry_build` | Build the production image (`linux/amd64`) | — |
| `artifact_registry_push` | Push the production image to Artifact Registry | ⚠️ |

## Variables

| Variable | Example |
|---|---|
| `GCP_PROJECT` | `my-project-id` |
| `GCP_REGION` | `europe-west1` |
| `ARTIFACTSREPO` | `my-artifacts` |

## Typical flow

`artifact_registry_auth` once per region (it registers that region's registry
address in Docker's configuration), `artifact_registry_create` +
`artifact_registry_role` once per project, then `artifact_registry_build` →
`artifact_registry_push` → [`cloudrun_deploy`](cloud_run.md).
