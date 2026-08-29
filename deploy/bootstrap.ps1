param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ProjectId,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Region
)

$ErrorActionPreference = 'Stop'
$repository = 'drift'
$apiRuntimeName = 'drift-api-runtime'
$demoRuntimeName = 'drift-demo-runtime'
$buildName = 'drift-build'
$apiRuntime = "$apiRuntimeName@$ProjectId.iam.gserviceaccount.com"
$demoRuntime = "$demoRuntimeName@$ProjectId.iam.gserviceaccount.com"
$buildServiceAccount = "$buildName@$ProjectId.iam.gserviceaccount.com"

$billingEnabled = gcloud billing projects describe $ProjectId --format 'value(billingEnabled)'
if ($billingEnabled -ne 'True') {
    throw "Billing is not enabled for $ProjectId. Link an active credit-backed billing account before provisioning."
}

gcloud config set project $ProjectId | Out-Null
gcloud services enable `
    run.googleapis.com `
    cloudbuild.googleapis.com `
    artifactregistry.googleapis.com `
    secretmanager.googleapis.com `
    billingbudgets.googleapis.com `
    firestore.googleapis.com `
    pubsub.googleapis.com `
    aiplatform.googleapis.com `
    logging.googleapis.com `
    iamcredentials.googleapis.com `
    cloudresourcemanager.googleapis.com `
    serviceusage.googleapis.com `
    --project $ProjectId

gcloud artifacts repositories describe $repository --location $Region --project $ProjectId 2>$null
if ($LASTEXITCODE -ne 0) {
    gcloud artifacts repositories create $repository `
        --repository-format docker `
        --location $Region `
        --description 'Drift Cloud Run images' `
        --project $ProjectId
}

gcloud firestore databases describe --database '(default)' --project $ProjectId 2>$null
if ($LASTEXITCODE -ne 0) {
    gcloud firestore databases create `
        --database '(default)' `
        --location $Region `
        --type firestore-native `
        --project $ProjectId
}

foreach ($account in @(
    @{ Name = $apiRuntimeName; Display = 'Drift API runtime' },
    @{ Name = $demoRuntimeName; Display = 'Drift replay runtime' },
    @{ Name = $buildName; Display = 'Drift Cloud Build identity' }
)) {
    $email = "$($account.Name)@$ProjectId.iam.gserviceaccount.com"
    gcloud iam service-accounts describe $email --project $ProjectId 2>$null
    if ($LASTEXITCODE -ne 0) {
        gcloud iam service-accounts create $account.Name `
            --display-name $account.Display `
            --project $ProjectId
    }
}

foreach ($role in @(
    'roles/aiplatform.user',
    'roles/datastore.user',
    'roles/logging.logWriter',
    'roles/secretmanager.secretAccessor'
)) {
    gcloud projects add-iam-policy-binding $ProjectId `
        --member "serviceAccount:$apiRuntime" `
        --role $role `
        --condition None `
        --quiet | Out-Null
}

gcloud projects add-iam-policy-binding $ProjectId `
    --member "serviceAccount:$demoRuntime" `
    --role roles/logging.logWriter `
    --condition None `
    --quiet | Out-Null

foreach ($role in @(
    'roles/artifactregistry.writer',
    'roles/logging.logWriter',
    'roles/run.admin',
    'roles/serviceusage.serviceUsageConsumer',
    'roles/storage.objectAdmin'
)) {
    gcloud projects add-iam-policy-binding $ProjectId `
        --member "serviceAccount:$buildServiceAccount" `
        --role $role `
        --condition None `
        --quiet | Out-Null
}

foreach ($runtime in @($apiRuntime, $demoRuntime)) {
    gcloud iam service-accounts add-iam-policy-binding $runtime `
        --member "serviceAccount:$buildServiceAccount" `
        --role roles/iam.serviceAccountUser `
        --project $ProjectId `
        --quiet | Out-Null
}

Write-Output 'Drift foundation is ready.'
Write-Output "Build identity: projects/$ProjectId/serviceAccounts/$buildServiceAccount"
Write-Output 'Next: load the three Secret Manager values, then submit deploy/cloudbuild.yaml.'
