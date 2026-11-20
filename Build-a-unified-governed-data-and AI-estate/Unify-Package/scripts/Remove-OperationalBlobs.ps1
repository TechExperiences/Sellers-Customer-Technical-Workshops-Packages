[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$StorageAccountName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Operational source files are only a transient Blob landing stage. They are removed
# after the Azure SQL load completes, leaving Analytical and BusinessApplication data.
$remaining = @(& az storage blob list --account-name $StorageAccountName --container-name data --auth-mode login `
    --prefix 'Operational/' --query '[].name' -o tsv | Where-Object { $_ })
if ($LASTEXITCODE -ne 0) { throw 'Could not list data/Operational blobs for cleanup.' }
if ($remaining.Count -eq 0) {
    Write-Host 'No Operational blobs remain to delete.' -ForegroundColor Green
    return
}

& az storage blob delete-batch --account-name $StorageAccountName --source data --pattern 'Operational/*' --auth-mode login --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Deleting data/Operational blobs failed.' }

$remaining = @(& az storage blob list --account-name $StorageAccountName --container-name data --auth-mode login `
    --prefix 'Operational/' --query '[].name' -o tsv | Where-Object { $_ })
if ($LASTEXITCODE -ne 0 -or $remaining.Count -ne 0) { throw 'Operational blob cleanup reported success but files still remain.' }
Write-Host 'Deleted data/Operational blobs after successful Azure SQL ingestion.' -ForegroundColor Green
