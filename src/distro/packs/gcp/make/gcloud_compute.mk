# ==============================================================================
# COMPUTE ENGINE (VM) COMMANDS
# ==============================================================================

vm_create: ## Create the VM (run iam_setup_service_account first if it needs GCP API access)
	$(call check_vars, INSTANCE GCP_PROJECT ZONE IMAGE_FAMILY IMAGE_PROJECT MACHINE_TYPE SA_NAME)
	$(call confirm_action, Create the VM (billed), INSTANCE GCP_PROJECT ZONE MACHINE_TYPE)
	@echo "🖥️ Creating VM $(INSTANCE) with service account $(SA_EMAIL)..."
	gcloud compute instances create $(INSTANCE) \
		--project=$(GCP_PROJECT) \
		--zone=$(ZONE) \
		--image-family=$(IMAGE_FAMILY) \
		--image-project=$(IMAGE_PROJECT) \
		--machine-type=$(MACHINE_TYPE) \
		--service-account=$(SA_EMAIL) \
		--scopes=https://www.googleapis.com/auth/cloud-platform

vm_run_script: ## Send and execute a shell script from the project on the VM (req: VM_SCRIPT)
	$(call check_vars, INSTANCE GCP_PROJECT ZONE VM_SCRIPT)
	$(call confirm_action, Run a script on the VM, INSTANCE GCP_PROJECT ZONE VM_SCRIPT)
	@echo "📦 Sending $(VM_SCRIPT) to VM..."
	gcloud compute scp $(VM_SCRIPT) $(INSTANCE):~/ \
		--project=$(GCP_PROJECT) \
		--zone=$(ZONE)
	@echo "⚙️ Executing on the VM (the script stays there if it fails)..."
	gcloud compute ssh $(INSTANCE) \
		--project=$(GCP_PROJECT) \
		--zone=$(ZONE) \
		--command="bash ~/$(notdir $(VM_SCRIPT))"
	@echo "🗑️ Cleaning up on the VM..."
	gcloud compute ssh $(INSTANCE) \
		--project=$(GCP_PROJECT) \
		--zone=$(ZONE) \
		--command="rm ~/$(notdir $(VM_SCRIPT))"

vm_connect: ## Connect to the VM via SSH with agent forwarding
	$(call check_vars, INSTANCE GCP_PROJECT ZONE)
	@echo "🔌 Connecting to $(INSTANCE)..."
	gcloud compute ssh $(INSTANCE) --project=$(GCP_PROJECT) --zone=$(ZONE) --ssh-flag="-A"

vm_start: ## Start the virtual machine (CPU billing resumes)
	$(call check_vars, INSTANCE GCP_PROJECT ZONE)
	@echo "🟢 Starting machine $(INSTANCE)..."
	gcloud compute instances start $(INSTANCE) \
		--project=$(GCP_PROJECT) \
		--zone=$(ZONE)

vm_stop: ## Stop the virtual machine (Save CPU billing)
	$(call check_vars, INSTANCE GCP_PROJECT ZONE)
	@echo "🔴 Stopping machine $(INSTANCE)... (CPU is no longer billed)"
	gcloud compute instances stop $(INSTANCE) \
		--project=$(GCP_PROJECT) \
		--zone=$(ZONE)

vm_delete: ## Delete the virtual machine permanently
	$(call check_vars, INSTANCE GCP_PROJECT ZONE)
	$(call confirm_action, Delete the VM permanently, INSTANCE GCP_PROJECT ZONE)
	@echo "💣 Deleting machine $(INSTANCE) permanently..."
	gcloud compute instances delete $(INSTANCE) \
		--project=$(GCP_PROJECT) \
		--zone=$(ZONE) \
		--quiet
