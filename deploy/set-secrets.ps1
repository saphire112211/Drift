param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ProjectId
)

$ErrorActionPreference = 'Stop'

function Add-SecretVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    gcloud secrets describe $Name --project $ProjectId 2>$null
    if ($LASTEXITCODE -ne 0) {
        gcloud secrets create $Name --replication-policy automatic --project $ProjectId | Out-Null
    }

    $gcloud = (Get-Command gcloud).Source
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $gcloud
    $start.ArgumentList.Add('secrets')
    $start.ArgumentList.Add('versions')
    $start.ArgumentList.Add('add')
    $start.ArgumentList.Add($Name)
    $start.ArgumentList.Add('--data-file=-')
    $start.ArgumentList.Add("--project=$ProjectId")
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.UseShellExecute = $false
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    [void]$process.Start()
    $process.StandardInput.Write($Value)
    $process.StandardInput.Close()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "Failed to add a version for $Name`: $($process.StandardError.ReadToEnd())"
    }
}

$values = @(
    @{ Name = 'drift-github-token'; Environment = 'DRIFT_GITHUB_TOKEN'; Value = $env:DRIFT_GITHUB_TOKEN }
    @{ Name = 'drift-slack-webhook'; Environment = 'DRIFT_SLACK_WEBHOOK_URL'; Value = $env:DRIFT_SLACK_WEBHOOK_URL }
    @{ Name = 'drift-demo-trigger'; Environment = 'DRIFT_DEMO_TRIGGER_TOKEN'; Value = $env:DRIFT_DEMO_TRIGGER_TOKEN }
)

foreach ($entry in $values) {
    if ([string]::IsNullOrWhiteSpace($entry.Value)) {
        throw "Set $($entry.Environment) in this shell before running this script."
    }
    Add-SecretVersion -Name $entry.Name -Value $entry.Value
}

Write-Output 'All Drift secrets have a current version. No secret values were printed or written to disk.'
