# ==========================================
# GOOGLE CLOUD CHEATSHEET
# requires: gcloud
# ==========================================
# The raw gcloud commands for the one-time setup, then the gmake targets that
# drive the same services — the full walkthrough lives in the pack's
# onboarding guide (packs/oh_my_cloud/docs/onboarding.md).
# Offered only while the CLI is installed, and the pack with it. Removed by
# hand (`sudo apt remove google-cloud-cli`), the sheet hides itself - which is
# what the header above is for: commands that would not run are not shown.

# --- 1. AUTHENTICATION (once per distro, lost if the distro is recreated) ---
gcloud auth login                              # Login 1: identify YOURSELF to the gcloud/bq tools (everything the Makefile calls) — browser flow
gcloud auth application-default login          # Login 2: identify YOURSELF to your Python code (google-cloud-* libraries)
gcloud auth list                               # Show which account gcloud is currently using
gcloud auth revoke                             # Revoke the CLI credentials of the current account

# --- 2. PROJECT & BILLING ---
gcloud projects list                           # List the projects your account can access
gcloud config get-value project                # Show the project gcloud considers active (the Makefile always passes --project explicitly)
gcloud config set project <PROJECT_ID>         # Set the active project for manually-typed gcloud commands
gcloud billing projects describe <PROJECT_ID>  # Check whether billing is enabled on a project

# --- 3. APIS & SERVICE ACCOUNTS ---
gcloud services list --enabled                 # List the APIs already enabled on the active project
gcloud iam service-accounts list               # List the service accounts (robot identities) of the active project
gcloud iam service-accounts keys create <FILE.json> --iam-account=<SA_EMAIL> # Create a JSON key for a service account (the bootcamp file) — treat it as a password

# --- 4. GOOGLE CLOUD PLATFORM (GCP - GENERAL) ---
gmake gcp_auth_cli                           # Authenticate the gcloud CLI (gcloud, bq) with your Google account
gmake gcp_auth_libs                          # Authenticate the Python client libraries (application-default credentials)
gmake gcp_project_list                       # List all accessible GCP projects
gmake gcp_enable_compute                     # Enable Compute Engine API for the active project
gmake gcp_enable_storage                     # Enable Cloud Storage API for the active project
gmake gcp_enable_bigquery                    # Enable BigQuery API for the active project
gmake gcp_enable_cloudrun                    # Enable Cloud Run API for the active project
gmake gcp_enable_artifact_registry           # Enable Artifact Registry API for the active project
gmake gcp_enable_apis                        # Enable all the APIs used by the template modules at once
gmake gcs_list_buckets                       # List all Google Cloud Storage (GCS) buckets
gmake gcs_create_bucket                      # Provision a new Cloud Storage bucket
gmake gcs_delete_bucket                      # Delete a Cloud Storage bucket
gmake iam_setup_service_account              # Create and configure an IAM service account

# --- 5. GOOGLE BIGQUERY ---
gmake bigquery_create_dataset                # Create the BigQuery dataset
gmake bigquery_create_table                  # Create a new table in BigQuery
gmake bigquery_show                          # Inspect table or dataset metadata
gmake bigquery_delete_table                  # Delete a specific table in BigQuery
gmake bigquery_delete_dataset                # Delete an entire dataset and its contents in BigQuery

# --- 6. GOOGLE CLOUD RUN ---
gmake cloudrun_deploy                        # Deploy container to Cloud Run (private by default; CLOUDRUN_PUBLIC=true for a public URL)
gmake cloudrun_logs                          # View and stream Cloud Run service logs
gmake cloudrun_list                          # List all active Cloud Run services
gmake cloudrun_url                           # Fetch public URL of the deployed API service
gmake cloudrun_delete                        # Delete Cloud Run service

# --- 6-B. CALLING A PRIVATE SERVICE (authenticated access) ---
curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" <SERVICE_URL> # Call a private Cloud Run service (identity token of the current account)
gcloud run services add-iam-policy-binding <SERVICE> --member=user:<EMAIL> --role=roles/run.invoker --region=<REGION> # Grant a user access to a private service
gcloud run services remove-iam-policy-binding <SERVICE> --member=allUsers --role=roles/run.invoker --region=<REGION> # Make an already-deployed public service private again

# --- 7. GOOGLE COMPUTE ENGINE (VM) ---
gmake vm_create                              # Provision a new Compute Engine virtual machine
gmake vm_run_script                          # Send and execute a shell script from the project on the VM (VM_SCRIPT=...)
gmake vm_connect                             # Open an SSH session into the virtual machine
gmake vm_start                               # Start a stopped virtual machine instance
gmake vm_stop                                # Gracefully shut down the virtual machine
gmake vm_delete                              # Permanently terminate and delete the virtual machine

# --- 8. DOCKER & ARTIFACT REGISTRY (the gcloud-driven half) ---
gmake artifact_registry_create               # Create repository in Google Artifact Registry
gmake artifact_registry_role                 # Configure IAM permissions for Artifact Registry
gmake artifact_registry_auth                 # Authenticate Docker client with Google Cloud credentials
gmake artifact_registry_build                # Build production-optimized Docker image
gmake artifact_registry_push                 # Push production image to Artifact Registry
