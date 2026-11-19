function Test-CaldovaDotNetSdk {
  param([Parameter(Mandatory)][string] $DotNetPath, [Parameter(Mandatory)][int] $MajorVersion)
  if (-not (Test-Path -LiteralPath $DotNetPath -PathType Leaf)) { return $false }
  $sdks = & $DotNetPath --list-sdks 2>$null
  if ($LASTEXITCODE -ne 0) { return $false }
  return [bool]($sdks | Where-Object { $_ -match "^$MajorVersion\." })
}

function Use-CaldovaDotNetRoot {
  param([Parameter(Mandatory)][string] $InstallDir)
  $env:DOTNET_ROOT = $InstallDir
  $env:DOTNET_MULTILEVEL_LOOKUP = '0'
  $pathEntries = @($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ -and ($_.TrimEnd('\') -ne $InstallDir.TrimEnd('\')) })
  $env:PATH = (@($InstallDir) + $pathEntries) -join [IO.Path]::PathSeparator
}

# Ensures a .NET SDK with the requested major version is usable in this process.
# Uses an existing machine/user SDK when present; otherwise installs one into the
# package-local .dotnet folder (no admin rights required) and prepends it to PATH.
function Initialize-CaldovaDotNetSdk {
  param(
    [Parameter(Mandatory)][string] $ProjectRoot,
    [int] $MajorVersion = 10
  )

  $existing = Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($existing -and (Test-CaldovaDotNetSdk -DotNetPath $existing.Source -MajorVersion $MajorVersion)) {
    Write-Host ".NET $MajorVersion SDK found: $($existing.Source)"
    return
  }

  $installDir = Join-Path $ProjectRoot '.dotnet'
  $localDotNet = Join-Path $installDir 'dotnet.exe'
  if (Test-CaldovaDotNetSdk -DotNetPath $localDotNet -MajorVersion $MajorVersion) {
    Write-Host ".NET $MajorVersion SDK found in package-local folder: $installDir"
    Use-CaldovaDotNetRoot -InstallDir $installDir
    return
  }

  Write-Host ".NET $MajorVersion SDK not found. Downloading it into $installDir (one-time)..."
  $installerPath = Join-Path ([IO.Path]::GetTempPath()) "dotnet-install-$([guid]::NewGuid().ToString('N')).ps1"
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $installerPath -UseBasicParsing
    & $installerPath -Channel "$MajorVersion.0" -InstallDir $installDir -NoPath
  }
  finally {
    if (Test-Path -LiteralPath $installerPath) { Remove-Item -LiteralPath $installerPath -Force }
  }

  if (-not (Test-CaldovaDotNetSdk -DotNetPath $localDotNet -MajorVersion $MajorVersion)) {
    throw ".NET $MajorVersion SDK installation failed. Install it manually from https://dotnet.microsoft.com/download/dotnet/$MajorVersion.0 and rerun."
  }
  Use-CaldovaDotNetRoot -InstallDir $installDir
  Write-Host ".NET $MajorVersion SDK installed: $(& $localDotNet --version)"
}
