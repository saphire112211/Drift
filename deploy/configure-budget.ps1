param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ProjectId,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$BillingAccountId,
    [ValidateRange(1, 1000000)][decimal]$Amount = 150,
    [ValidatePattern('^[A-Z]{3}$')][string]$CurrencyCode = 'USD'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$projectNumber = gcloud projects describe $ProjectId --format 'value(projectNumber)'
$displayName = "Drift hackathon - $ProjectId"
$existing = gcloud billing budgets list `
    --billing-account $BillingAccountId `
    --billing-project $ProjectId `
    --filter "displayName='$displayName'" `
    --format 'value(name)'

if (-not $existing) {
    gcloud billing budgets create `
        --billing-account $BillingAccountId `
        --billing-project $ProjectId `
        --display-name $displayName `
        --budget-amount "${Amount}${CurrencyCode}" `
        --filter-projects "projects/$projectNumber" `
        --credit-types-treatment exclude-all-credits `
        --threshold-rule percent=0.25 `
        --threshold-rule percent=0.5 `
        --threshold-rule percent=0.8 `
        --threshold-rule percent=0.9 `
        --threshold-rule percent=1.0
}

Write-Output "Budget alerts are configured for $ProjectId at 25%, 50%, 80%, 90%, and 100% of $CurrencyCode $Amount."
Write-Output 'The budget tracks gross usage before promotional credits are deducted.'
Write-Output 'Budgets alert; they do not impose a hard spending cap.'
