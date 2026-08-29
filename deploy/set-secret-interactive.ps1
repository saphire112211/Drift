param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ProjectId,
    [Parameter(Mandatory = $true)]
    [ValidateSet('drift-github-token', 'drift-slack-webhook', 'drift-demo-trigger')]
    [string]$Name
)

$ErrorActionPreference = 'Stop'

gcloud secrets describe $Name --project $ProjectId 2>$null
if ($LASTEXITCODE -ne 0) {
    gcloud secrets create $Name --replication-policy automatic --project $ProjectId | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to create Secret Manager secret $Name." }
}

$secureValue = Read-Host "Paste the value for $Name (input is hidden)" -AsSecureString
if ($secureValue.Length -eq 0) { throw 'The secret value cannot be empty.' }

$pointer = [IntPtr]::Zero
$plainValue = $null
try {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
    $plainValue = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)

    $gcloud = (Get-Command gcloud.cmd -ErrorAction Stop).Source
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = 'cmd.exe'
    $start.ArgumentList.Add('/d')
    $start.ArgumentList.Add('/s')
    $start.ArgumentList.Add('/c')
    $start.ArgumentList.Add("`"$gcloud`" secrets versions add `"$Name`" --data-file=- --project=`"$ProjectId`"")
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.UseShellExecute = $false

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    [void]$process.Start()
    $process.StandardInput.Write($plainValue)
    $process.StandardInput.Close()
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "Failed to add a version for $Name`: $standardError"
    }
} finally {
    if ($pointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
    $plainValue = $null
    $secureValue.Dispose()
}

Write-Output "$Name now has a current Secret Manager version. No secret value was printed or written to disk."
