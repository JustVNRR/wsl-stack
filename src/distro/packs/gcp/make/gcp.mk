# ==============================================================================
# GCP INFRASTRUCTURE & IAM COMMANDS
# ==============================================================================

# Derived - so never list it in check_vars. $(value SA_EMAIL) returns the text
# of this definition, which is never empty, and the check could never fire: the
# variables to test are SA_NAME and GCP_PROJECT.
SA_EMAIL = $(SA_NAME)@$(GCP_PROJECT).iam.gserviceaccount.com

gcp_auth_cli: ## Authenticate the gcloud CLI (gcloud, bq) with your Google account
	@echo "🔑 Opening the Google login for the gcloud CLI..."
	gcloud auth login

gcp_auth_libs: ## Authenticate the Python client libraries (application-default credentials)
	@echo "🔑 Opening the Google login for the application-default credentials..."
	gcloud auth application-default login

gcp_project_list: ## List all GCP projects available to your account
	@echo "📋 Listing GCP projects..."
	gcloud projects list
	# Useful alternatives:
	# gcloud projects list --format="value(projectId)" # lists only IDs
	# gcloud config get-value project # shows only the active project ID

gcp_enable_compute: ## Enable the Compute Engine API for the project
	$(call check_vars, GCP_PROJECT)
	$(call confirm_action, Enable the Compute Engine API, GCP_PROJECT)
	@echo "⚙️ Enabling Compute Engine API..."
	gcloud services enable compute.googleapis.com --project=$(GCP_PROJECT)

gcp_enable_storage: ## Enable the Cloud Storage API for the project
	$(call check_vars, GCP_PROJECT)
	$(call confirm_action, Enable the Cloud Storage API, GCP_PROJECT)
	@echo "⚙️ Enabling Cloud Storage API..."
	gcloud services enable storage.googleapis.com --project=$(GCP_PROJECT)

gcp_enable_bigquery: ## Enable the BigQuery API for the project
	$(call check_vars, GCP_PROJECT)
	$(call confirm_action, Enable the BigQuery API, GCP_PROJECT)
	@echo "⚙️ Enabling BigQuery API..."
	gcloud services enable bigquery.googleapis.com --project=$(GCP_PROJECT)

gcp_enable_cloudrun: ## Enable the Cloud Run API for the project
	$(call check_vars, GCP_PROJECT)
	$(call confirm_action, Enable the Cloud Run API, GCP_PROJECT)
	@echo "⚙️ Enabling Cloud Run API..."
	gcloud services enable run.googleapis.com --project=$(GCP_PROJECT)

gcp_enable_artifact_registry: ## Enable the Artifact Registry API for the project
	$(call check_vars, GCP_PROJECT)
	$(call confirm_action, Enable the Artifact Registry API, GCP_PROJECT)
	@echo "⚙️ Enabling Artifact Registry API..."
	gcloud services enable artifactregistry.googleapis.com --project=$(GCP_PROJECT)

gcp_enable_apis: ## Enable every API the gmake modules use (the five above at once)
	$(call check_vars, GCP_PROJECT)
	$(call confirm_action, Enable every API the template uses, GCP_PROJECT)
	@echo "⚙️ Enabling all template APIs (compute, storage, BigQuery, Cloud Run, Artifact Registry)..."
	gcloud services enable \
		compute.googleapis.com \
		storage.googleapis.com \
		bigquery.googleapis.com \
		run.googleapis.com \
		artifactregistry.googleapis.com \
		--project=$(GCP_PROJECT)

gcs_list_buckets: ## List all Cloud Storage buckets in the project
	$(call check_vars, GCP_PROJECT)
	@echo "🪣 Listing Cloud Storage buckets..."
	gcloud storage ls --project=$(GCP_PROJECT)

gcs_create_bucket: ## Create a new Cloud Storage bucket
	$(call check_vars, BUCKET_NAME GCP_REGION GCP_PROJECT)
	$(call confirm_action, Create the Cloud Storage bucket, BUCKET_NAME GCP_REGION GCP_PROJECT)
	@echo "🪣 Creating bucket gs://$(BUCKET_NAME)..."
	gcloud storage buckets create gs://$(BUCKET_NAME) \
		--location=$(GCP_REGION) \
		--project=$(GCP_PROJECT)

gcs_delete_bucket: ## Delete the Cloud Storage bucket and all its contents
	$(call check_vars, BUCKET_NAME GCP_PROJECT)
	$(call confirm_action, Delete the bucket and everything in it, BUCKET_NAME GCP_PROJECT)
	@echo "💣 Deleting bucket gs://$(BUCKET_NAME)..."
	gcloud storage rm --recursive gs://$(BUCKET_NAME) --project=$(GCP_PROJECT)

# No way out here: a pack leaves from Windows - `.\wsl.ps1 remove_pack` runs
# remove.sh, then deletes this folder, the file you are reading included. A
# target that has to erase what defines it can only half do the job.
# ~/.config/gcloud keeps the logins: the user's data, not the pack's.

iam_setup_service_account: ## Create the Service Account and assign IAM roles
	$(call check_vars, SA_NAME GCP_PROJECT)
	$(call confirm_action, Create the service account and its IAM roles, SA_NAME SA_EMAIL GCP_PROJECT)
	@# Describe first, create only when absent - same shape as
	@# artifact_registry_create, for the same reason: `|| true` used to hide
	@# every failure (permission denied, API not enabled) behind a success, and
	@# the bindings below then failed on an account that was never created.
	@if gcloud iam service-accounts describe "$(SA_EMAIL)" --project="$(GCP_PROJECT)" >/dev/null 2>&1; then \
		echo "ℹ️  Service account $(SA_EMAIL) already exists."; \
	else \
		echo "🤖 Creating Service Account $(SA_NAME)..."; \
		gcloud iam service-accounts create $(SA_NAME) \
			--display-name="VM service account" \
			--project=$(GCP_PROJECT); \
	fi
	@echo "🔐 Adding BigQuery Data Editor role..."
	gcloud projects add-iam-policy-binding $(GCP_PROJECT) \
		--member="serviceAccount:$(SA_EMAIL)" \
		--role="roles/bigquery.dataEditor" \
		--quiet
	@echo "🔐 Adding Cloud Storage Object Admin role..."
	gcloud projects add-iam-policy-binding $(GCP_PROJECT) \
		--member="serviceAccount:$(SA_EMAIL)" \
		--role="roles/storage.objectAdmin" \
		--quiet
