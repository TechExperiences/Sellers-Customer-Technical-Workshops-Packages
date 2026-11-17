[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$FabricCapacityResourceId,
    [string]$WorkspaceName,
    [string]$LakehouseName = 'Caldova_Lakehouse',
    [string]$FabricSqlDatabaseName = 'Caldova_SQLDatabase'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$python = Get-Command python -ErrorAction Stop

if (-not $WorkspaceName) {
    # This fallback also creates a distinct workspace for callers outside .\up.ps1.
    # The standard pipeline supplies the more traceable UTC run suffix itself.
    $WorkspaceName = "rg-Build-Unify-$([guid]::NewGuid().ToString('N').Substring(0, 12))"
}

$result = & $python.Source (Join-Path $PSScriptRoot 'deploy_fabric_foundation.py') `
    --capacity-resource-id $FabricCapacityResourceId `
    --workspace $WorkspaceName `
    --lakehouse $LakehouseName `
    --sql-database $FabricSqlDatabaseName
if ($LASTEXITCODE -ne 0) { throw 'Fabric workspace, Lakehouse, or Fabric SQL database provisioning failed.' }

# The Python command emits one JSON object so subsequent pipeline steps can use the
# immutable workspace and Lakehouse IDs rather than looking up a display name again.
return (($result -join [Environment]::NewLine) | ConvertFrom-Json)
