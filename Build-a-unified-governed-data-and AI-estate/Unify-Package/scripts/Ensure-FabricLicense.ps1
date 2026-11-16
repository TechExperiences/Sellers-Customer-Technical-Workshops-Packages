[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$UserPrincipalName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-GraphRest {
    param(
        [Parameter(Mandatory)] [ValidateSet('GET', 'POST')] [string]$Method,
        [Parameter(Mandatory)] [string]$Url,
        [string]$BodyFile
    )

    $arguments = @('rest', '--method', $Method, '--url', $Url, '--resource', 'https://graph.microsoft.com', '--headers', 'Content-Type=application/json')
    # On Windows, an inline JSON string can lose its double quotes while az.cmd
    # forwards it to Azure CLI. A file keeps the assignLicense request valid.
    if ($BodyFile) { $arguments += @('--body', "@$BodyFile") }
    $response = & az @arguments
    if ($LASTEXITCODE -ne 0) { throw "Microsoft Graph request failed: $Method $Url" }
    return $response | ConvertFrom-Json
}

function Get-ExistingFabricPowerBiEntitlement {
    param([Parameter(Mandatory)] [object[]]$LicenseDetails)

    foreach ($license in $LicenseDetails) {
        $skuPartNumber = [string]$license.skuPartNumber
        if ($skuPartNumber -match '(?i)(FABRIC|POWER_?BI|POWERBI)') {
            return [PSCustomObject]@{
                Description = $skuPartNumber
                SkuPartNumber = $skuPartNumber
            }
        }

        # Power BI Pro can be bundled in a broader Microsoft 365 licence. For
        # example, Microsoft 365 E5 exposes it as BI_AZURE_P2, not as a top-level
        # POWER_BI_PRO SKU. Only enabled user service plans count as entitlement.
        $matchingPlan = @($license.servicePlans | Where-Object {
            $_.appliesTo -eq 'User' -and
            $_.provisioningStatus -eq 'Success' -and
            $_.servicePlanName -match '(?i)^(BI_AZURE_P[0-9]+|POWER_?BI|POWERBI|FABRIC)'
        } | Select-Object -First 1)
        if ($matchingPlan.Count -gt 0) {
            return [PSCustomObject]@{
                Description = "$skuPartNumber / $($matchingPlan[0].servicePlanName)"
                SkuPartNumber = $skuPartNumber
            }
        }
    }

    return $null
}

$encodedUpn = [System.Uri]::EscapeDataString($UserPrincipalName)
$licenseDetails = Invoke-GraphRest -Method GET -Url "https://graph.microsoft.com/v1.0/users/$encodedUpn/licenseDetails?`$select=skuId,skuPartNumber,servicePlans"
$assignedFabricLicense = Get-ExistingFabricPowerBiEntitlement -LicenseDetails @($licenseDetails.value)
if ($assignedFabricLicense) {
    Write-Host "Existing Fabric/Power BI entitlement $($assignedFabricLicense.Description) is already assigned to $UserPrincipalName." -ForegroundColor Green
    return
}

$subscribedSkus = Invoke-GraphRest -Method GET -Url 'https://graph.microsoft.com/v1.0/subscribedSkus?$select=skuId,skuPartNumber,prepaidUnits,consumedUnits'
$freeOrTrialSkus = @($subscribedSkus.value | Where-Object {
    $skuPartNumber = [string]$_.skuPartNumber
    $skuPartNumber -in @('FABRIC_FREE', 'POWER_BI_STANDARD') -or
    $skuPartNumber -match '(?i)(FABRIC|POWER_?BI|POWERBI).*(FREE|TRIAL)'
} | Where-Object { ([int]$_.prepaidUnits.enabled - [int]$_.consumedUnits) -gt 0 })
$sku = @($freeOrTrialSkus | Select-Object -First 1)
if (-not $sku) {
    throw 'No assignable free or trial Fabric/Power BI license is exposed by this tenant. Microsoft Graph cannot create or enroll a tenant into a new 60-day trial; it can only assign licenses that the tenant already exposes. Enable the Fabric/Power BI trial or free license once in the Microsoft 365/Fabric admin experience, then rerun .\up.ps1.'
}

$body = @{ addLicenses = @(@{ skuId = $sku.skuId }); removeLicenses = @() } | ConvertTo-Json -Compress
$bodyFile = New-TemporaryFile
try {
    Set-Content -LiteralPath $bodyFile -Value $body -Encoding utf8NoBOM -NoNewline
    [void](Invoke-GraphRest -Method POST -Url "https://graph.microsoft.com/v1.0/users/$encodedUpn/assignLicense" -BodyFile $bodyFile)
}
finally {
    Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue
}
Write-Host "Assigned free or trial Fabric/Power BI license $($sku.skuPartNumber) to $UserPrincipalName." -ForegroundColor Green
