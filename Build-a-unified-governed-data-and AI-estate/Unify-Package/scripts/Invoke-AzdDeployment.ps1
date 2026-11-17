[CmdletBinding()]
param(
    [string]$EnvFile = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Import-DotEnv {
    param([Parameter(Mandatory)] [string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Environment file not found: $Path. Copy .env.example to .env and populate it first." }
    $values = [ordered]@{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -notmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { throw "Invalid .env entry: $line" }
        $name, $value = $Matches[1], $Matches[2].Trim()
        if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$name] = $value
    }
    return $values
}

function Invoke-Checked {
    param([Parameter(Mandatory)] [scriptblock]$Command, [Parameter(Mandatory)] [string]$FailureMessage)
    & $Command
    if ($LASTEXITCODE -ne 0) { throw $FailureMessage }
}

function Get-TokenObjectId {
    param([Parameter(Mandatory)] [string]$AccessToken)

    $tokenParts = $AccessToken.Split('.')
    if ($tokenParts.Count -lt 2) { throw 'Azure access token is invalid.' }
    $payload = $tokenParts[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) {
        0 { break }
        2 { $payload += '==' }
        3 { $payload += '=' }
        default { throw 'Azure access token payload is invalid.' }
    }
    $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
    if (-not $claims.oid) { throw 'Azure access token did not contain the deployment identity object ID.' }
    return [string]$claims.oid
}

$environment = Import-DotEnv -Path (Resolve-Path -LiteralPath $EnvFile)
foreach ($required in @('AZURE_ENV_NAME', 'AZURE_SUBSCRIPTION_ID', 'AZURE_LOCATION', 'AZURE_RESOURCE_GROUP', 'FABRIC_CAPACITY_ADMIN_UPN', 'SQL_ADMINISTRATOR_LOGIN', 'SQL_ADMINISTRATOR_PASSWORD')) {
    $value = [string]$environment[$required]
    if (-not $value -or $value -match '^<.*>$') { throw "Set a real value for $required in $EnvFile before deployment." }
}

if (-not (Get-Command az -ErrorAction Ignore) -or -not (Get-Command azd -ErrorAction Ignore)) {
    throw 'Both Azure CLI (az) and Azure Developer CLI (azd) are required.'
}

foreach ($entry in $environment.GetEnumerator()) { Set-Item -Path "Env:$($entry.Key)" -Value $entry.Value }

& az account show --only-show-errors 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    $tenantArgument = if ($environment.AZURE_TENANT_ID -and $environment.AZURE_TENANT_ID -notmatch '^<.*>$') { @('--tenant', $environment.AZURE_TENANT_ID) } else { @() }
    Invoke-Checked -Command { & az login @tenantArgument --only-show-errors } -FailureMessage 'Azure CLI sign-in did not complete.'
}
Invoke-Checked -Command { & az account set --subscription $environment.AZURE_SUBSCRIPTION_ID } -FailureMessage "Cannot select subscription $($environment.AZURE_SUBSCRIPTION_ID). Sign in to the lab tenant and verify access."

# The post-provision scripts use Azure CLI data-plane authentication, so grant Blob
# access to that exact identity. This must happen before azd up: azd validates all
# Bicep parameters before executing pre-provision hooks.
$signedInIdentity = & az account show --query user -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $signedInIdentity.type) { throw 'Could not determine the signed-in Azure identity type.' }
$deploymentPrincipalType = switch ($signedInIdentity.type) {
    'servicePrincipal' { 'ServicePrincipal'; break }
    'user' { 'User'; break }
    default { throw "Unsupported Azure identity type for Blob role assignment: $($signedInIdentity.type)" }
}
$managementAccessToken = (& az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv).Trim()
if ($LASTEXITCODE -ne 0 -or -not $managementAccessToken) { throw 'Could not acquire an Azure Resource Manager token for the deployment identity.' }
$deploymentPrincipalObjectId = Get-TokenObjectId -AccessToken $managementAccessToken

# A new logical server is intentional for every run.  The UTC timestamp makes the
# name traceable; the random suffix protects against two runs starting in one second.
$runStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')
$runSuffix = -join ((48..57) + (97..122) | Get-Random -Count 5 | ForEach-Object { [char]$_ })
$environment['SQL_SERVER_NAME'] = "sql-operational-$runStamp$runSuffix"
$env:SQL_SERVER_NAME = $environment['SQL_SERVER_NAME']
Write-Host "Creating a new operational SQL Server: $($environment['SQL_SERVER_NAME'])" -ForegroundColor Cyan

& azd auth login --check-status 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    $tenantArgument = if ($environment.AZURE_TENANT_ID -and $environment.AZURE_TENANT_ID -notmatch '^<.*>$') { @('--tenant-id', $environment.AZURE_TENANT_ID) } else { @() }
    Invoke-Checked -Command { & azd auth login @tenantArgument } -FailureMessage 'Azure Developer CLI sign-in did not complete.'
}

$azdEnvironmentPath = Join-Path (Split-Path -Parent $PSScriptRoot) ".azure/$($environment.AZURE_ENV_NAME)/.env"
if (-not (Test-Path -LiteralPath $azdEnvironmentPath)) {
    Invoke-Checked -Command { & azd env new $environment.AZURE_ENV_NAME --subscription $environment.AZURE_SUBSCRIPTION_ID --location $environment.AZURE_LOCATION --no-prompt } -FailureMessage 'Could not create the Azure Developer CLI environment.'
} else {
    Invoke-Checked -Command { & azd env select $environment.AZURE_ENV_NAME } -FailureMessage 'Could not select the Azure Developer CLI environment.'
}

foreach ($entry in $environment.GetEnumerator()) {
    Invoke-Checked -Command { & azd env set $entry.Key $entry.Value --environment $environment.AZURE_ENV_NAME } -FailureMessage "Could not save $($entry.Key) to the azd environment."
}

Invoke-Checked -Command { & azd env set DEPLOYMENT_PRINCIPAL_OBJECT_ID $deploymentPrincipalObjectId --environment $environment.AZURE_ENV_NAME } -FailureMessage 'Could not save DEPLOYMENT_PRINCIPAL_OBJECT_ID to the azd environment.'
Invoke-Checked -Command { & azd env set DEPLOYMENT_PRINCIPAL_TYPE $deploymentPrincipalType --environment $environment.AZURE_ENV_NAME } -FailureMessage 'Could not save DEPLOYMENT_PRINCIPAL_TYPE to the azd environment.'

# The Fabric capacity ARM resource consumes this value from the azd environment
# while resolving infra/main.parameters.json.  Do an explicit final write and a
# read-back check so a stale or blank saved azd value can never become
# administration.members: [""] during provisioning.
$fabricCapacityAdminUpn = ([string]$environment.FABRIC_CAPACITY_ADMIN_UPN).Trim()
Invoke-Checked -Command { & azd env set FABRIC_CAPACITY_ADMIN_UPN $fabricCapacityAdminUpn --environment $environment.AZURE_ENV_NAME } -FailureMessage 'Could not save FABRIC_CAPACITY_ADMIN_UPN to the azd environment.'

$effectiveAzdValues = & azd env get-values --environment $environment.AZURE_ENV_NAME
if ($LASTEXITCODE -ne 0) { throw 'Could not read the azd environment after saving FABRIC_CAPACITY_ADMIN_UPN.' }
$effectiveAdminLine = $effectiveAzdValues | Where-Object { $_ -match '^FABRIC_CAPACITY_ADMIN_UPN=' } | Select-Object -First 1
if (-not $effectiveAdminLine) { throw 'FABRIC_CAPACITY_ADMIN_UPN was not persisted in the azd environment; provisioning was not started.' }
$effectiveAdminUpn = ($effectiveAdminLine -replace '^FABRIC_CAPACITY_ADMIN_UPN=', '').Trim().Trim('"').Trim("'")
if ([string]::IsNullOrWhiteSpace($effectiveAdminUpn) -or $effectiveAdminUpn -ne $fabricCapacityAdminUpn) {
    throw 'FABRIC_CAPACITY_ADMIN_UPN in the azd environment is blank or differs from .env; provisioning was not started.'
}
Write-Host 'Verified Fabric capacity administrator from .env in the azd environment.' -ForegroundColor Cyan

Invoke-Checked -Command { & azd up --environment $environment.AZURE_ENV_NAME --no-prompt } -FailureMessage 'azd up failed. Review the preceding deployment output for the failing resource or permission.'

# Keep Fabric deployment under this one-command wrapper rather than an azd lifecycle
# hook.  Some azd executions reported successful ARM provisioning without emitting
# the postprovision hook, which left Azure resources in place but no Fabric items.
# Invoking the existing script directly makes Fabric creation visible and causes
# .\up.ps1 to fail if any workspace, Lakehouse, ingestion, model, report, or Data
# Agent step fails.
Write-Host 'Azure provisioning completed. Starting the required Fabric post-provision stage...' -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'Post-Provision.ps1')
if ($LASTEXITCODE -ne 0) {
    throw 'Fabric post-provisioning failed. Review the preceding Fabric output for the failing step.'
}
Write-Host 'Fabric post-provision stage completed.' -ForegroundColor Green
