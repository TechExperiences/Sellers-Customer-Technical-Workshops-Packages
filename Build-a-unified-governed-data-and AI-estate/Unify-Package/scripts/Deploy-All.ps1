[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$ParametersFile,
    [Parameter(Mandatory)] [string]$SqlAdministratorPassword,
    [Parameter(Mandatory)] [string]$SqlEntraAdministratorUpn
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$parameters = Get-Content -LiteralPath $ParametersFile -Raw | ConvertFrom-Json
$values = $parameters.parameters
$resourceGroup = $values.resourceGroupName.value
$storageAccount = $values.storageAccountName.value
$sqlServer = $values.sqlServerName.value
$sqlDatabase = $values.sqlDatabaseName.value

Write-Host 'Phase 1/4: Provisioning Azure foundation and Fabric capacity.' -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'Deploy-Foundation.ps1') -ParametersFile $ParametersFile -SqlAdministratorPassword $SqlAdministratorPassword

Write-Host 'Phase 2/4: Uploading validated source folders to Blob Storage.' -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'Upload-SourceData.ps1') -StorageAccountName $storageAccount

Write-Host 'Phase 3/4: Configuring SQL Entra administrator and loading OperationalData.' -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'Configure-SqlEntraAdmin.ps1') -SqlServerName $sqlServer -AdministratorUpn $SqlEntraAdministratorUpn -ResourceGroupName $resourceGroup
$env:AZURE_SQL_ACCESS_TOKEN = az account get-access-token --resource https://database.windows.net --query accessToken -o tsv
if ($LASTEXITCODE -ne 0 -or -not $env:AZURE_SQL_ACCESS_TOKEN) { throw 'Could not acquire an Entra access token for Azure SQL.' }
try {
    & (Get-Command python -ErrorAction Stop).Source (Join-Path $PSScriptRoot 'load_operational_data.py') `
        --server "$sqlServer.database.windows.net" --database $sqlDatabase --reset
    if ($LASTEXITCODE -ne 0) { throw 'Operational data load failed.' }
} finally {
    Remove-Item Env:AZURE_SQL_ACCESS_TOKEN -ErrorAction SilentlyContinue
}

Write-Host 'Phase 4/4: Azure foundation deployment completed.' -ForegroundColor Green
Write-Host 'The F16 Fabric capacity is retained, but this workflow creates no Fabric workspace or Fabric items.' -ForegroundColor Yellow
