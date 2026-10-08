# Cloud Run

[← Back to the README](../../../../../README.md#makefile-gmake)

Deploy containerized services to Google Cloud Run, and operate them.

## Targets

| Target | Action | Confirmation |
|---|---|---|
| `cloudrun_deploy` | Deploy the container to Cloud Run (private unless `CLOUDRUN_PUBLIC=true`) | ⚠️ |
| `cloudrun_list` | List all active Cloud Run services in the project | — |
| `cloudrun_url` | Retrieve the live URL of the deployed API | — |
| `cloudrun_logs` | Read the last 50 log lines of the service | — |
| `cloudrun_delete` | Delete the service and take the API offline | ⚠️ destructive |

## Calling a private service

```bash
curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" "$SERVICE_URL"
```

Grant the invoker role to another identity:

```bash
gcloud run services add-iam-policy-binding <SERVICE> \
    --member=user:<EMAIL> --role=roles/run.invoker --region=<REGION>
```

```bash
gcloud run services remove-iam-policy-binding <SERVICE> \
    --member=allUsers --role=roles/run.invoker --region=<REGION>
```

## Variables

| Variable | Required by | Example |
|---|---|---|
| `GAR_IMAGE` | every target except `cloudrun_list` | `my-api` |
| `GCP_REGION` | every target except `cloudrun_list` | `europe-west1` |
| `GCP_PROJECT` | every target | `my-project-id` |
| `ARTIFACTSREPO` | `cloudrun_deploy` | `my-artifacts` |
| `CLOUDRUN_MEMORY` | `cloudrun_deploy` | `2Gi` |
| `CLOUDRUN_PUBLIC` | `cloudrun_deploy` | empty (private) or `true` |

