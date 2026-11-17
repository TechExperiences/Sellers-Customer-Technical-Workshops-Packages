[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$WorkspaceId,
    [Parameter(Mandatory)] [string]$PrincipalId,
    [Parameter(Mandatory)] [ValidateSet('User', 'ServicePrincipal')] [string]$PrincipalType,
    [Parameter(Mandatory)] [ValidateSet('Admin', 'Contributor')] [string]$Role,
    [Parameter(Mandatory)] [string]$PrincipalDescription,
    [Parameter(Mandatory)] [string]$FabricAccessToken
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$headers = @{ Authorization = "Bearer $FabricAccessToken" }
$roleAssignmentsUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/roleAssignments"

# The Fabric Core API takes Entra object IDs directly, avoiding the legacy Power BI
# membership API's separate Microsoft Graph application-ID lookup.
$roleAssignments = Invoke-RestMethod -Method Get -Uri $roleAssignmentsUri -Headers $headers
$existing = @($roleAssignments.value | Where-Object { $_.principal.id -eq $PrincipalId })
if ($existing) {
    Write-Host "$PrincipalDescription already has Fabric workspace access." -ForegroundColor Green
    return
}

$body = @{
    principal = @{
        id   = $PrincipalId
        type = $PrincipalType
    }
    role = $Role
} | ConvertTo-Json -Compress

# Kept as defense-in-depth for any residual propagation delay, though the Fabric Core
# API's direct object-ID lookup removes the failure mode retries previously masked.
$maxAttempts = 4
$delaySeconds = 15
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
        Invoke-RestMethod -Method Post -Uri $roleAssignmentsUri -Headers $headers -ContentType 'application/json' -Body $body | Out-Null
        Write-Host "Granted $PrincipalDescription the $Role role in Fabric workspace $WorkspaceId." -ForegroundColor Green
        return
    } catch {
        if ($attempt -eq $maxAttempts) { throw }
        Write-Host "Granting $PrincipalDescription Fabric workspace access attempt $attempt of $maxAttempts failed ($($_.Exception.Message)); retrying in $delaySeconds seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds $delaySeconds
        $delaySeconds = [Math]::Min($delaySeconds * 2, 120)
    }
}
