[CmdletBinding()]
param(
    [string]$EnvFile = (Join-Path $PSScriptRoot '.env')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ResourceGroupName = 'rg-caldova-iq'
$RequiredLocation = 'westus2'

function Invoke-Checked {
    param(
        [Parameter(Mandatory)] [scriptblock]$Command,
        [Parameter(Mandatory)] [string]$FailureMessage
    )

    & $Command
    if ($LASTEXITCODE -ne 0) { throw $FailureMessage }
}

function Import-DotEnv {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Environment file was not found: $Path. Copy .env.example to .env and set its values."
    }

    $values = [ordered]@{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -notmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            throw "Invalid .env entry: $line"
        }

        $name, $value = $Matches[1], $Matches[2].Trim()
        if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$name] = $value
    }

    return $values
}

function Test-ServicePrincipalAzureCliSession {
    param(
        [Parameter(Mandatory)] [string]$ClientId,
        [Parameter(Mandatory)] [string]$TenantId
    )

    $accountJson = & az account show --only-show-errors --output json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $accountJson) { return $false }

    try {
        $account = $accountJson | ConvertFrom-Json
        return $account.user.type -eq 'servicePrincipal' -and
            $account.user.name -eq $ClientId -and
            $account.tenantId -eq $TenantId
    } catch {
        return $false
    }
}

function Get-TokenObjectId {
    param([Parameter(Mandatory)] [string]$AccessToken)

    $segments = $AccessToken.Split('.')
    if ($segments.Length -lt 2) { throw 'Azure access token is not a JWT.' }

    $payload = $segments[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) {
        2 { $payload += '==' }
        3 { $payload += '=' }
        1 { throw 'Azure access token payload is invalid.' }
    }

    $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
    if (-not $claims.oid) { throw 'Azure access token did not contain the service principal object ID.' }
    return [string]$claims.oid
}

if (-not (Get-Command az -ErrorAction Ignore)) {
    throw 'Azure CLI (az) is required. Install it, reopen PowerShell, and run this script again.'
}

$configuration = Import-DotEnv -Path (Resolve-Path -LiteralPath $EnvFile)
foreach ($required in @('AZURE_SUBSCRIPTION_ID', 'AZURE_TENANT_ID', 'AZURE_CLIENT_ID', 'AZURE_CLIENT_SECRET', 'AZURE_LOCATION', 'FABRIC_CAPACITY_ADMIN_UPN', 'FABRIC_CAPACITY_ID')) {
    $value = [string]$configuration[$required]
    if (-not $value -or $value -match '^<.*>$') {
        throw "Set a real value for $required in $EnvFile."
    }
    Set-Item -Path "Env:$required" -Value $value
}

$location = $env:AZURE_LOCATION.ToLowerInvariant()
if ($location -ne $RequiredLocation) {
    throw "AZURE_LOCATION must be $RequiredLocation for this deployment, matching the Amplify IQ README."
}

$capacityId = $env:FABRIC_CAPACITY_ID.ToLowerInvariant()
if ($capacityId -notmatch '^[a-z0-9]{1,40}$') {
    throw 'FABRIC_CAPACITY_ID must contain only lowercase letters and numbers, with no spaces or special characters.'
}

$capacityName = "fabriccapacity$capacityId"
if ($capacityName.Length -gt 63) {
    throw 'The generated Fabric capacity name is longer than 63 characters. Use a shorter FABRIC_CAPACITY_ID.'
}

if (Test-ServicePrincipalAzureCliSession -ClientId $env:AZURE_CLIENT_ID -TenantId $env:AZURE_TENANT_ID) {
    Write-Host 'Using the existing Azure CLI session for the configured service principal.' -ForegroundColor Cyan
} else {
    Write-Host 'Signing in to Azure CLI with the configured service principal...' -ForegroundColor Cyan
    Invoke-Checked {
        az login --service-principal --username $env:AZURE_CLIENT_ID --password $env:AZURE_CLIENT_SECRET --tenant $env:AZURE_TENANT_ID --only-show-errors 1>$null
    } 'Azure CLI service-principal sign-in did not complete.'
}

Invoke-Checked {
    az account set --subscription $env:AZURE_SUBSCRIPTION_ID --only-show-errors
} "Could not select subscription $($env:AZURE_SUBSCRIPTION_ID)."

$managementAccessToken = (& az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv).Trim()
if ($LASTEXITCODE -ne 0 -or -not $managementAccessToken) {
    throw 'Could not acquire an Azure Resource Manager access token.'
}
$deploymentServicePrincipalObjectId = Get-TokenObjectId -AccessToken $managementAccessToken

Write-Host "Ensuring resource group $ResourceGroupName exists in $location..." -ForegroundColor Cyan
Invoke-Checked {
    az group create --name $ResourceGroupName --location $location --only-show-errors 1>$null
} "Could not create or validate resource group $ResourceGroupName."

Write-Host "Creating or validating F16 Fabric capacity $capacityName in $location..." -ForegroundColor Cyan
Invoke-Checked {
    az deployment group create --resource-group $ResourceGroupName --name 'amplify-fabric-capacity' `
        --template-file (Join-Path $PSScriptRoot 'infra/main.bicep') `
        --parameters capacityName=$capacityName location=$location capacityAdministratorUpn=$env:FABRIC_CAPACITY_ADMIN_UPN deploymentServicePrincipalObjectId=$deploymentServicePrincipalObjectId `
        --only-show-errors 1>$null
} 'Fabric capacity deployment failed.'

$capacityResourceId = (& az resource show --resource-group $ResourceGroupName --resource-type Microsoft.Fabric/capacities --name $capacityName --query id --output tsv --only-show-errors).Trim()
if ($LASTEXITCODE -ne 0 -or -not $capacityResourceId) {
    throw "Fabric capacity $capacityName was not found after deployment."
}

$capacityState = ''
for ($attempt = 1; $attempt -le 60; $attempt++) {
    $capacityState = (& az resource show --resource-group $ResourceGroupName --resource-type Microsoft.Fabric/capacities --name $capacityName --query properties.state --output tsv --only-show-errors).Trim()
    if ($LASTEXITCODE -eq 0 -and $capacityState -eq 'Active') { break }
    if ($capacityState -eq 'Paused') { throw "Fabric capacity $capacityName was created in the Paused state." }
    Write-Host "Waiting for Fabric capacity $capacityName to become Active (attempt $attempt/60)..." -ForegroundColor DarkYellow
    Start-Sleep -Seconds 10
}

if ($capacityState -ne 'Active') {
    throw "Fabric capacity $capacityName was deployed but did not become Active within 10 minutes. Check the capacity in Azure portal."
}

Write-Host "Completed. Resource group: $ResourceGroupName; Fabric capacity: $capacityName; State: Active." -ForegroundColor Green

