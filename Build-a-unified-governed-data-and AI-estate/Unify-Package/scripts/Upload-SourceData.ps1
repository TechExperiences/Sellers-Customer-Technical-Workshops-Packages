[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$StorageAccountName,
    [string]$ContainerName = 'data'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'Test-SourceData.ps1') -PackageRoot $packageRoot

function Invoke-BlobUploadWhenReady {
    param(
        [Parameter(Mandatory)] [string]$SourceFolder,
        [Parameter(Mandatory)] [string]$DestinationPath
    )

    # Azure RBAC data-plane grants can take a short time to propagate after the
    # storage account and role assignment are created in the same deployment.
    for ($attempt = 1; $attempt -le 24; $attempt++) {
        az storage blob upload-batch --account-name $StorageAccountName --auth-mode login `
            --destination $ContainerName --destination-path $DestinationPath --source $SourceFolder --overwrite true
        if ($LASTEXITCODE -eq 0) { return }
        if ($attempt -eq 24) { throw "Could not upload $DestinationPath after waiting for Storage Blob Data Contributor access." }
        Write-Host "Storage Blob access is not ready for $DestinationPath; waiting 5 seconds (attempt $attempt/24)..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
}

foreach ($folder in @('Analytical', 'BusinessApplication', 'Operational')) {
    $source = Join-Path $packageRoot $folder
    Invoke-BlobUploadWhenReady -SourceFolder $source -DestinationPath $folder
}
