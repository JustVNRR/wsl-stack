# GCP Onboarding

[← Back to the README](../../../README.md#optional-tooling)

## Step 0 — outside the distro, once

A Google account, a **GCP project**, and **billing enabled** on that project
(`console.cloud.google.com`). Without billing, BigQuery, Cloud Run, Artifact
Registry and VMs refuse to run — even inside their free tiers. On a personal
project you are the Owner and nothing below will ask you for permissions; on a
company project, ask your administrator for the roles of the modules you use.

## Step 1 — install the pack, then authenticate the CLI

The image ships no pack at all, and not every project uses Google Cloud: a pack
arrives on a living instance, from Windows — pick the instance, then `gcp`:

```powershell
.\wsl.ps1 add_pack
```

It registers Google's APT repository before installing the package, and copies
the pack's files — targets, cheatsheets, environment samples — into the
instance. `.\wsl.ps1 remove_pack` takes both back out.

Run `gmake` again: the GCP targets are there. They call `gcloud`
and `bq` under your Google account — this one-time login authorizes them.

```bash
gmake gcp_auth_cli
```

A browser window opens (WSL interop — if none opens, copy the URL gcloud
prints into any browser).

## Step 2 — check what you can see

```bash
gmake gcp_project_list
```

Lists the projects your account can access — your first successful call.

## Step 3 — fill the two env contracts

Once per machine — your shared defaults, the GCP block among them:

```bash
gmake env_global_enable
```

then fill `GCP_REGION` and `ZONE` at minimum.

Once per project — its identity, in the project folder:

```bash
gmake env_project_enable
```

then fill `GCP_PROJECT` at minimum; add each module's variables as you need
them. Both commands read the samples — the GCP pack's and the shell's — and
only append what the file does not define yet: existing values are never
touched. Run them again after adding a pack.

`gmake` always passes `--project` explicitly, so you never need
`gcloud config set project` — the `.env` file is the single source of truth.

## Step 4 — enable the APIs

A fresh project has most Google Cloud APIs turned **off**; calling a disabled
one fails with a `SERVICE_DISABLED` error. Enable everything the modules use:

```bash
gmake gcp_enable_apis
```

Or one service at a time: `gcp_enable_compute`, `gcp_enable_storage`,
`gcp_enable_bigquery`, `gcp_enable_cloudrun`, `gcp_enable_artifact_registry`.
Enabling is free and idempotent.

## Step 5 — authenticate the Python client libraries

The `google-cloud-*` libraries imported by your scripts, notebooks and tests
use their own credential, separate from step 1: the *application-default
credentials*. This one-time login creates it.

```bash
gmake gcp_auth_libs
```

If `GOOGLE_APPLICATION_CREDENTIALS` is set in `.env.global`, the libraries
use that service-account key file instead and this step is unnecessary.

## Step 6 — first steps per workflow

From here, what you run depends on the workflow — each module page documents
its full flow.

- **Docker → Artifact Registry** ([`artifact_registry.md`](artifact_registry.md),
  [`docker.md`](../../devops/docs/docker.md)): run `artifact_registry_auth` once per region and
  create the repository once per project; then build and push your production
  image.
- **Cloud Run** ([`cloud_run.md`](cloud_run.md)): deploy a pushed
  image; services are private unless `CLOUDRUN_PUBLIC=true`.
- **VMs** ([`gcloud_compute.md`](gcloud_compute.md)): create, connect,
  and set up the machine — `vm_run_script` sends a script of your choice
  (`VM_SCRIPT=...`) from the project to the VM; the project owns the script.
- **BigQuery** ([`bigquery.md`](bigquery.md)): create the dataset,
  then the tables.

## Good to know

- **The CLI and the credentials live inside the distro** (`/usr/bin/gcloud`,
  `~/.config/gcloud`). Recreating the distro loses both — run
  `.\wsl.ps1 add_pack`, then redo steps 1 and 5.
- Operational targets refuse to run outside a project folder under
  `~/projects` — the message says so. `GMAKE_ANYWHERE=1` bypasses the gate
  for unconventional setups.
- Free tiers exist but they all require billing to be enabled. Compute VMs are
  billed per second of uptime, hence the explicit `vm_start` / `vm_stop`
  targets.
