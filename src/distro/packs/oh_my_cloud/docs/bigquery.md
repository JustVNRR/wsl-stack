# BigQuery

[← Back to the README](../../../../../README.md#makefile-gmake)

Datasets and tables.

## Targets

| Target | Action | Confirmation |
|---|---|---|
| `bigquery_create_dataset` | Create the BigQuery dataset | ⚠️ |
| `bigquery_create_table` | Create a new table in the dataset (`TABLE_NAME`) | ⚠️ |
| `bigquery_show` | Show details of the project, dataset, or table | — |
| `bigquery_delete_table` | Delete a specific table (`TABLE_NAME`) | ⚠️ |
| `bigquery_delete_dataset` | Delete the dataset **and all its tables** | ⚠️ destructive |

## Variables

| Variable | Required by | Example / default |
|---|---|---|
| `GCP_PROJECT` | all targets | `my-project-id` |
| `BQ_DATASET` | all but the project-level `bigquery_show` | `my_dataset` |
| `BQ_REGION` | `bigquery_create_dataset`, `bigquery_create_table` | `EU` (default in `.env.global`) |
| `TABLE_NAME` | `bigquery_create_table`, `bigquery_delete_table`, optional for `bigquery_show` | `my_table` |
