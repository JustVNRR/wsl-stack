# ==============================================================================
# DOCKER COMMANDS
# ==============================================================================
# Everything that runs on docker alone. The production image is another matter
# - its tag names an Artifact Registry path - so building and pushing it live in
# the oh_my_cloud pack's artifact_registry.mk.
#
# Both targets build ONE project: they run from its root, and the variables
# they check identify it.

docker_build_local: ## Build the Docker image locally for testing
	$(call check_vars, DOCKER_BASE_IMAGE PACKAGE_NAME DOCKER_LOCAL_IMAGE)
	@echo "🐳 Building local Docker image $(DOCKER_LOCAL_IMAGE):dev..."
	docker build \
		--build-arg DOCKER_BASE_IMAGE=$(DOCKER_BASE_IMAGE) \
		--build-arg PACKAGE_NAME=$(PACKAGE_NAME) \
		--tag=$(DOCKER_LOCAL_IMAGE):dev .

docker_run_local: ## Run the local Docker container on port 8080
	$(call check_vars, DOCKER_LOCAL_IMAGE)
	@echo "🏃♂️ Running container $(DOCKER_LOCAL_IMAGE):dev..."
	@echo "👉 Go to http://localhost:8080"
	docker run -it -e PORT=8000 -p 8080:8000 $(DOCKER_LOCAL_IMAGE):dev
