# Google Cloud deployment

## Prerequisites

- A Google Cloud project with billing and Artifact Registry.
- `gcloud` authenticated to the intended project.
- The public GitHub `saphire112211/Drift` repository containing
  `demo_target/prompts/system.md`.
- A fine-grained GitHub token and Slack incoming webhook.

The repository includes idempotent provisioning scripts. They stop when the project is not
linked to an active billing account, so deployment cannot silently move to a different,
card-backed project.

Provision APIs, Artifact Registry, Firestore, and least-privilege build/runtime identities:

```powershell
pwsh deploy/bootstrap.ps1 -ProjectId data-shard-504916-r8 -Region us-central1
```

Load credentials without putting secret values in shell history, files, build substitutions,
screenshots, or logs. Set them only in the current shell, run the loader, then remove them:

```powershell
$env:DRIFT_GITHUB_TOKEN = '<fine-grained token>'
$env:DRIFT_SLACK_WEBHOOK_URL = '<channel webhook>'
$env:DRIFT_DEMO_TRIGGER_TOKEN = '<random bearer secret>'
pwsh deploy/set-secrets.ps1 -ProjectId data-shard-504916-r8
Remove-Item Env:DRIFT_GITHUB_TOKEN,Env:DRIFT_SLACK_WEBHOOK_URL,Env:DRIFT_DEMO_TRIGGER_TOKEN
```

The GitHub token must be restricted to `saphire112211/Drift` with Contents, Issues, and Pull
Requests write permissions. The Slack webhook must be restricted to the demo incident
channel.

## Deploy

The deployment targets Google Cloud project `data-shard-504916-r8` and the repository
substitutions are already configured. Run:

```powershell
gcloud builds submit --config deploy/cloudbuild.yaml `
  --service-account projects/data-shard-504916-r8/serviceAccounts/drift-build@data-shard-504916-r8.iam.gserviceaccount.com
pwsh deploy/configure-events.ps1 -ProjectId data-shard-504916-r8 -Region us-central1
```

The configuration script creates the event and dead-letter topics, an OIDC push identity,
the authenticated subscription, and the required Cloud Run invoker binding.

`drift-demo-target` is private. `drift-api` obtains a Google-signed identity token using its
dedicated runtime identity for every replay request. The public dashboard shares the API
service, while Pub/Sub and demo-trigger routes independently enforce authentication.

## Verify

```bash
gcloud run services describe drift-api --region us-central1
gcloud run services describe drift-demo-target --region us-central1
gcloud pubsub topics describe drift-incidents
curl "$(gcloud run services describe drift-api --region us-central1 --format='value(status.url)')/healthz"
```

The health response used in the demo must show:

- `reasoning_backend: gemini_adk`
- `gemini_model: gemini-3.5-flash`
- `state_backend: firestore`
- `action_mode: live`
- `live_actions_ready: true`
- `sandbox_authenticated: true`

Run the live proof and duplicate-delivery check:

```powershell
pwsh deploy/smoke-test.ps1 -ProjectId data-shard-504916-r8 -Region us-central1
```

After capturing deployment proof, keep the UI available but scale idle services to zero.

## Cost controls

Both Cloud Run services use minimum instances `0` and are capped at one instance. The live
hackathon billing account is denominated in INR and has INR 14,346.94 of promotional credit.
Its production safety controls are:

- `Drift Vertex AI safety cap`: INR 10,000 enforced spend cap, scoped to Vertex AI in
  `data-shard-504916-r8`, with notifications at 50%, 80%, and 100%.
- `Drift total gross usage alerts`: INR 14,000 project-wide budget that excludes credits
  from its calculation, with notifications at 25%, 50%, 80%, 90%, and 100%.

Billing-account administrators or Costs Managers can reproduce the project-wide alert
budget with:

```powershell
pwsh deploy/configure-budget.ps1 -ProjectId data-shard-504916-r8 `
  -BillingAccountId 0199CF-F58002-E56B60 -Amount 14000 -CurrencyCode INR
```

This creates alerts at 25%, 50%, 80%, 90%, and 100% of gross usage before credits. Verify
the alert recipients in Cloud Billing. A principal with only Billing Account User can link
projects but cannot create budgets; use the billing-owner console in that case.
Keep the maximum instance caps in `deploy/cloudbuild.yaml`,
retain the Pub/Sub dead-letter limit of five deliveries, and delete unused Artifact Registry
images after judging. Never treat a budget as a hard service quota.

## Failure recovery

Required GitHub failures are retried three times inside one delivery. If they remain failed,
the API returns `503`; Pub/Sub redelivers with bounded backoff and moves the durable incident
to `drift-incidents-dlq` after five delivery attempts. Slack failures are recorded in the
action ledger but do not invalidate a successfully opened draft pull request. To replay a
DLQ incident, fix the external dependency, publish a new source event ID, and retain the old
failed run for audit history.
