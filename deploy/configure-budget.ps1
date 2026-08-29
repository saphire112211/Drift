param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ProjectId,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$BillingAccountId,
    [ValidateRange(1, 10000)][decimal]$AmountUsd = 150
)

$ErrorActionPreference = 'Stop'
$projectNumber = gcloud projects describe $ProjectId --format 'value(projectNumber)'
$displayName = "Drift hackathon - $ProjectId"
$existing = gcloud billing budgets list `
    --billing-account $BillingAccountId `
    --filter "displayName='$displayName'" `
    --format 'value(name)'

if (-not $existing) {
    gcloud billing budgets create `
        --billing-account $BillingAccountId `
        --display-name $displayName `
        --budget-amount "${AmountUsd}USD" `
        --filter-projects "projects/$projectNumber" `
        --threshold-rule percent=0.25 `
        --threshold-rule percent=0.5 `
        --threshold-rule percent=0.8 `
        --threshold-rule percent=0.9 `
        --threshold-rule percent=1.0
}

Write-Output "Budget alerts are configured for $ProjectId at 25%, 50%, 80%, 90%, and 100% of USD $AmountUsd."
Write-Output 'Budgets alert; they do not impose a hard spending cap.'
