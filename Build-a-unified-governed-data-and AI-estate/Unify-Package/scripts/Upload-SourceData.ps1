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

    # The role is deployed with the new storage account. Wait for Azure RBAC
    # data-plane propagation instead of failing the first upload immediately.
    for ($attempt = 1; $attempt -le 60; $attempt++) {
        az storage blob upload-batch --account-name $StorageAccountName --auth-mode login `
            --destination $ContainerName --destination-path $DestinationPath --source $SourceFolder --overwrite true
        if ($LASTEXITCODE -eq 0) { return }
        if ($attempt -eq 60) { throw "Could not upload $DestinationPath after waiting for Storage Blob Data Contributor access." }
        Write-Host "Storage Blob access is not ready for $DestinationPath; waiting 5 seconds (attempt $attempt/60)..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
}

foreach ($folder in @('Analytical', 'BusinessApplication', 'Operational')) {
    $source = Join-Path $packageRoot $folder
    Invoke-BlobUploadWhenReady -SourceFolder $source -DestinationPath $folder
}
