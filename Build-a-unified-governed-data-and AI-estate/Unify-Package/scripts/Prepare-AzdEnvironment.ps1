[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:FABRIC_CAPACITY_ADMIN_UPN) {
    $upn = az account show --query user.name -o tsv
    if (-not $upn) { throw 'Could not determine the signed-in Azure user. Run az login first.' }
    azd env set FABRIC_CAPACITY_ADMIN_UPN $upn | Out-Null
    $env:FABRIC_CAPACITY_ADMIN_UPN = $upn
}

if (-not $env:SQL_ADMINISTRATOR_PASSWORD) {
    $securePassword = Read-Host 'Create a SQL administrator password for this deployment' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    try { $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    azd env set SQL_ADMINISTRATOR_PASSWORD $plainPassword | Out-Null
    $env:SQL_ADMINISTRATOR_PASSWORD = $plainPassword
}

# UNIFY-SP-SUPPORT
$operator = $env:FABRIC_CAPACITY_ADMIN_UPN
$signedIn = az account show --query user -o json | ConvertFrom-Json
$deploymentPrincipalType = if ($signedIn.type -eq 'servicePrincipal') { 'ServicePrincipal' } else { 'User' }
$deploymentToken = (az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv).Trim()
if ($LASTEXITCODE -ne 0 -or -not $deploymentToken) { throw 'Could not determine the object ID of the deployment identity.' }
$deploymentPayload = $deploymentToken.Split('.')[1].Replace('-', '+').Replace('_', '/')
switch ($deploymentPayload.Length % 4) { 2 { $deploymentPayload += '==' } 3 { $deploymentPayload += '=' } }
$deploymentPrincipalObjectId = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($deploymentPayload)) | ConvertFrom-Json).oid
if (-not $deploymentPrincipalObjectId) { throw 'The deployment access token does not contain an object ID.' }
if ($signedIn.type -eq 'servicePrincipal') {
    $token = (az account get-access-token --resource https://database.windows.net --query accessToken -o tsv).Trim()
    $payload = $token.Split('.')[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
    $operator = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json).oid
}
azd env set FABRIC_CAPACITY_ADMIN_OPERATOR $operator | Out-Null
$env:FABRIC_CAPACITY_ADMIN_OPERATOR = $operator
azd env set DEPLOYMENT_PRINCIPAL_OBJECT_ID $deploymentPrincipalObjectId | Out-Null
azd env set DEPLOYMENT_PRINCIPAL_TYPE $deploymentPrincipalType | Out-Null
$env:DEPLOYMENT_PRINCIPAL_OBJECT_ID = $deploymentPrincipalObjectId
$env:DEPLOYMENT_PRINCIPAL_TYPE = $deploymentPrincipalType
