# ==============================================================================
# ARTIFACT REGISTRY — THE PRODUCTION IMAGE
# ==============================================================================
# Everything here needs a GCP project, so none of it can run without the Google
# CLI: three targets call `gcloud`, and the two that call `docker` only tag and
# push to a `-docker.pkg.dev` path that `gcloud auth configure-docker` unlocks.
# The container itself is not a Google concern: building and running it on your
# machine lives in the devops pack's docker.mk, with the variables that name it.

artifact_registry_create: ## Create the Docker repository in Artifact Registry
	$(call check_vars, ARTIFACTSREPO GCP_REGION GCP_PROJECT)
	$(call confirm_action, Create the Artifact Registry repository, ARTIFACTSREPO GCP_REGION GCP_PROJECT)
	@# Describe first and create only when it is absent: the target stays
	@# re-runnable, and a creation that really fails now fails the run - the
	@# `|| true` it replaces reported every failure (API disabled, permission
	@# denied, bad location) as a success, and the push found out much later.
	@if gcloud artifacts repositories describe $(ARTIFACTSREPO) \
		--location=$(GCP_REGION) \
		--project=$(GCP_PROJECT) >/dev/null 2>&1; then \
		echo "ℹ️  Repository $(ARTIFACTSREPO) already exists."; \
	else \
		echo "📦 Creating Artifact Registry repository $(ARTIFACTSREPO)..."; \
		gcloud artifacts repositories create $(ARTIFACTSREPO) \
			--repository-format=docker \
			--location=$(GCP_REGION) \
			--description="Docker repository $(ARTIFACTSREPO) for project $(GCP_PROJECT)" \
			--project=$(GCP_PROJECT); \
	fi

artifact_registry_role: ## Grant yourself permission to push to Artifact Registry
	$(call check_vars, GCP_PROJECT)
	$(call confirm_action, Grant the Artifact Registry Writer role, GCP_PROJECT)
	@echo "🔐 Adding Artifact Registry Writer role to your account..."
	gcloud projects add-iam-policy-binding $(GCP_PROJECT) \
		--member="user:$$(gcloud config get-value account)" \
		--role="roles/artifactregistry.writer"

artifact_registry_auth: ## Configure Docker to authenticate with Google Cloud
	$(call check_vars, GCP_REGION)
	@echo "🔑 Configuring Docker authentication for GCP..."
	gcloud auth configure-docker $(GCP_REGION)-docker.pkg.dev --quiet

artifact_registry_build: ## Build the Docker image for production (linux/amd64)
	$(call check_vars, DOCKER_BASE_IMAGE PACKAGE_NAME GCP_REGION GCP_PROJECT ARTIFACTSREPO GAR_IMAGE)
	@echo "🏗️ Building production image..."
	docker build \
		--platform linux/amd64 \
		--build-arg DOCKER_BASE_IMAGE=$(DOCKER_BASE_IMAGE) \
		--build-arg PACKAGE_NAME=$(PACKAGE_NAME) \
		-t $(GCP_REGION)-docker.pkg.dev/$(GCP_PROJECT)/$(ARTIFACTSREPO)/$(GAR_IMAGE):prod \
		.

artifact_registry_push: ## Push the production image to Artifact Registry
	$(call check_vars, GCP_REGION GCP_PROJECT ARTIFACTSREPO GAR_IMAGE)
	$(call confirm_action, Push the production image to Artifact Registry, GCP_REGION GCP_PROJECT ARTIFACTSREPO GAR_IMAGE)
	@echo "🚀 Pushing image to Artifact Registry..."
	docker push $(GCP_REGION)-docker.pkg.dev/$(GCP_PROJECT)/$(ARTIFACTSREPO)/$(GAR_IMAGE):prod
