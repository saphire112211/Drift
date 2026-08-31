param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ProjectId,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Region,
    [string]$EventId = "live-smoke-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
)

$ErrorActionPreference = 'Stop'
$apiUrl = gcloud run services describe drift-api `
    --project $ProjectId `
    --region $Region `
    --format 'value(status.url)'
if (-not $apiUrl) { throw 'drift-api is not deployed.' }

$health = Invoke-RestMethod -Uri "$apiUrl/v1/health"
if (
    $health.reasoning_backend -ne 'gemini_adk' -or
    $health.state_backend -ne 'firestore' -or
    $health.action_mode -ne 'live' -or
    -not $health.live_actions_ready
) {
    throw "Health configuration is not live-ready: $($health | ConvertTo-Json -Compress)"
}

$demoToken = gcloud secrets versions access latest `
    --secret drift-demo-trigger `
    --project $ProjectId
$headers = @{ Authorization = "Bearer $demoToken" }
$response = Invoke-RestMethod `
    -Uri "$apiUrl/v1/demo/incidents" `
    -Method Post `
    -Headers $headers `
    -ContentType 'application/json' `
    -Body (@{ event_id = $EventId } | ConvertTo-Json)
if ($response.stage -ne 'awaiting_review' -or $response.duplicate) {
    throw "First delivery did not reach awaiting_review: $($response | ConvertTo-Json -Compress)"
}

$run = Invoke-RestMethod -Uri "$apiUrl/v1/incidents/$($response.incident_id)"
if (-not $run.issue_url -or -not $run.pull_request_url) {
    throw 'The live run did not create both a GitHub issue and a draft pull request.'
}

$duplicate = Invoke-RestMethod `
    -Uri "$apiUrl/v1/demo/incidents" `
    -Method Post `
    -Headers $headers `
    -ContentType 'application/json' `
    -Body (@{ event_id = $EventId } | ConvertTo-Json)
if (-not $duplicate.duplicate -or $duplicate.incident_id -ne $response.incident_id) {
    throw 'Duplicate delivery was not deduplicated.'
}

[pscustomobject]@{
    service_url = $apiUrl
    incident_id = $response.incident_id
    stage = $response.stage
    issue_url = $run.issue_url
    pull_request_url = $run.pull_request_url
    duplicate_delivery_suppressed = $duplicate.duplicate
    build_revision = $health.build_revision
    gemini_model = $health.gemini_model
} | ConvertTo-Json
