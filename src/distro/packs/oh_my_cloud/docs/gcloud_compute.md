# Compute Engine (VMs)

[← Back to the README](../../../../../README.md#makefile-gmake)

Provision and operate virtual machines — the billing angle is made explicit
at every step.

## Targets

| Target | Action | Confirmation |
|---|---|---|
| `vm_create` | Create the VM (call `iam_setup_service_account` separately if it needs GCP API access) | ⚠️ billed |
| `vm_run_script` | Send and execute a shell script from the project on the VM | ⚠️ |
| `vm_connect` | Connect to the VM via SSH with agent forwarding | — |
| `vm_start` | Start the VM (CPU billing resumes) | — |
| `vm_stop` | Stop the VM (CPU no longer billed) | — |
| `vm_delete` | Delete the VM permanently | ⚠️ destructive |

`vm_run_script` sends a script of your choice (`VM_SCRIPT`, path relative to
the project root) to the VM and executes it — the project owns the script, so
put it in the repo (e.g. `scripts/setup_vm.sh`). The script is removed from
the VM after a successful run, and left in place if it fails so you can SSH
in and debug.

The VM runs as the service account `$(SA_EMAIL)`, which is not provisioned
automatically: when the VM needs GCP API access (BigQuery, Cloud Storage),
run [`iam_setup_service_account`](gcp.md) first.

## Variables

| Variable | Required by | Example / default |
|---|---|---|
| `INSTANCE` | all targets | `my-vm-instance` |
| `GCP_PROJECT` | all targets | `my-project-id` |
| `ZONE` | all targets | `europe-west1-b` |
| `MACHINE_TYPE` | `vm_create` | `e2-standard-2` |
| `IMAGE_FAMILY` | `vm_create` | `ubuntu-2204-lts` (default) |
| `IMAGE_PROJECT` | `vm_create` | `ubuntu-os-cloud` (default) |
| `SA_NAME` | `vm_create`, `iam_setup_service_account` | `my-project-vm-sa` |
| `VM_SCRIPT` | `vm_run_script` | `scripts/setup_vm.sh` |
