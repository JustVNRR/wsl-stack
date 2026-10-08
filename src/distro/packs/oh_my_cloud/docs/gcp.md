# GCP Infrastructure & IAM

[← Back to the README](../../../../../README.md#makefile-gmake)

Projects, Cloud Storage buckets, and service accounts — the ground floor of
the GCP modules. All targets read the cascading `.env.global` / `.env`
configuration, which [`env_global_enable` and `env_project_enable`](../../../../../docs/make/env.md)
assemble from the samples the shell and the packs ship.

New to GCP entirely? Start with the [onboarding guide](onboarding.md).

## Targets

| Target | Action | Confirmation |
|---|---|---|
| `gcp_auth_cli` | Authenticate the gcloud CLI (`gcloud`, `bq`) with your Google account | — |
| `gcp_auth_libs` | Authenticate the Python client libraries (application-default credentials) | — |
| `gcp_project_list` | List all GCP projects available to your account | — |
| `gcp_enable_compute` | Enable the Compute Engine API for the project | ⚠️ |
| `gcp_enable_storage` | Enable the Cloud Storage API for the project | ⚠️ |
| `gcp_enable_bigquery` | Enable the BigQuery API for the project | ⚠️ |
| `gcp_enable_cloudrun` | Enable the Cloud Run API for the project | ⚠️ |
| `gcp_enable_artifact_registry` | Enable the Artifact Registry API for the project | ⚠️ |
| `gcp_enable_apis` | Enable every API the gmake modules use (the five above at once) | ⚠️ |
| `gcs_list_buckets` | List all Cloud Storage buckets in the project | — |
| `gcs_create_bucket` | Create a new Cloud Storage bucket | ⚠️ |
| `gcs_delete_bucket` | Delete a bucket **and all its contents** | ⚠️ destructive |
| `iam_setup_service_account` | Create the service account and assign IAM roles | ⚠️ |

`iam_setup_service_account` grants the BigQuery Data Editor and Cloud Storage
Object Admin roles. It does not run automatically: call it explicitly before
`vm_create` when the VM needs GCP API access (see
[Compute Engine](gcloud_compute.md)).

## Variables

| Variable | Required by | Example |
|---|---|---|
| `GCP_PROJECT` | most targets | `my-project-id` |
| `GCP_REGION` | `gcs_create_bucket` | `europe-west1` |
| `BUCKET_NAME` | `gcs_create_bucket`, `gcs_delete_bucket` | `my-data-bucket` |
| `SA_NAME` | `iam_setup_service_account` | `my-project-vm-sa` |

`SA_EMAIL` is derived automatically:
`$(SA_NAME)@$(GCP_PROJECT).iam.gserviceaccount.com`.
