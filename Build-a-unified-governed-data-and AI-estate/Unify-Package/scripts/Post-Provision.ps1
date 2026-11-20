[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$resourceGroup = if ($env:AZURE_RESOURCE_GROUP) { $env:AZURE_RESOURCE_GROUP } else { 'rg-Build-Unify' }

# When the deployment is signed in as a service principal, it temporarily becomes
# the Azure SQL Entra administrator for the OperationalData load. The configured
# user is restored as the SQL Entra administrator after the load completes.
$signedInAccount = az account show --query user -o json | ConvertFrom-Json
$runningAsServicePrincipal = ($signedInAccount.type -eq 'servicePrincipal')

function Get-TokenObjectId {
    param([Parameter(Mandatory)] [string]$AccessToken)
    # The "oid" claim is the object id that Azure SQL compares with the Entra admin SID.
    $payload = $AccessToken.Split('.')[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
    return ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json).oid
}

function Get-AzureAccessToken {
    param(
        [Parameter(Mandatory)] [string]$Resource,
        [Parameter(Mandatory)] [string]$Purpose
    )

    $accessToken = (& az account get-access-token --resource $Resource --query accessToken -o tsv).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $accessToken) { throw "Could not acquire an Entra access token for $Purpose." }
    return $accessToken
}

$storageAccount = az storage account list --resource-group $resourceGroup --query '[0].name' -o tsv
$sqlServer = $env:SQL_SERVER_NAME
if (-not $storageAccount -or -not $sqlServer) {
    throw 'Expected Storage Account and Azure SQL Server were not found after provisioning.'
}

& az sql server show --resource-group $resourceGroup --name $sqlServer --only-show-errors 1>$null
if ($LASTEXITCODE -ne 0) { throw "The SQL Server created for this run was not found: $sqlServer" }

& (Join-Path $PSScriptRoot 'Upload-SourceData.ps1') -StorageAccountName $storageAccount
if ($runningAsServicePrincipal) {
    $operatorObjectId = Get-TokenObjectId -AccessToken (Get-AzureAccessToken -Resource 'https://database.windows.net' -Purpose 'Azure SQL')
    az sql server ad-admin create --resource-group $resourceGroup --server $sqlServer `
        --display-name $signedInAccount.name --object-id $operatorObjectId
    if ($LASTEXITCODE -ne 0) { throw 'Could not make the deploying service principal the Azure SQL Entra administrator.' }
    Write-Host 'Waiting for the Entra administrator change to take effect...' -ForegroundColor Yellow
    Start-Sleep -Seconds 90
} else {
    & (Join-Path $PSScriptRoot 'Configure-SqlEntraAdmin.ps1') -SqlServerName $sqlServer -AdministratorUpn $env:FABRIC_CAPACITY_ADMIN_UPN -ResourceGroupName $resourceGroup
}

& (Get-Command python -ErrorAction Stop).Source -m pip install --disable-pip-version-check -q -r (Join-Path $packageRoot 'requirements.txt')
$env:AZURE_SQL_ACCESS_TOKEN = Get-AzureAccessToken -Resource 'https://database.windows.net' -Purpose 'Azure SQL'
try {
    & (Get-Command python -ErrorAction Stop).Source (Join-Path $PSScriptRoot 'load_operational_data.py') --server "$sqlServer.database.windows.net" --reset
    if ($LASTEXITCODE -ne 0) { throw 'Operational data load failed.' }
} finally {
    Remove-Item Env:AZURE_SQL_ACCESS_TOKEN -ErrorAction SilentlyContinue
}
if ($runningAsServicePrincipal) {
    & (Join-Path $PSScriptRoot 'Configure-SqlEntraAdmin.ps1') -SqlServerName $sqlServer -AdministratorUpn $env:FABRIC_CAPACITY_ADMIN_UPN -ResourceGroupName $resourceGroup
}

& (Join-Path $PSScriptRoot 'Remove-OperationalBlobs.ps1') -StorageAccountName $storageAccount

Write-Host 'Deployment completed successfully. Analytical and BusinessApplication data uploaded to Azure Storage, OperationalData loaded into Azure SQL, and the F16 Fabric capacity is ready.' -ForegroundColor Green
