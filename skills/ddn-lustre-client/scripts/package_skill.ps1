param(
  [Parameter(Mandatory = $true)]
  [string]$DebDir,

  [string]$OutputZip = ""
)

$ErrorActionPreference = "Stop"

$skillRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$assetDebDir = Join-Path $skillRoot "assets/debs"
New-Item -ItemType Directory -Force -Path $assetDebDir | Out-Null

$required = @(
  "lustre-client-utils_2.14.0-ddn154-1_amd64.deb",
  "lustre-client-modules-6.8.0-124-generic_2.14.0-ddn154-1_amd64.deb",
  "lustre-dev_2.14.0-ddn154-1_amd64.deb"
)

$sourceDebDir = Resolve-Path -LiteralPath $DebDir
foreach ($name in $required) {
  $src = Join-Path $sourceDebDir $name
  if (-not (Test-Path -LiteralPath $src)) {
    throw "Missing required package: $src"
  }
  Copy-Item -LiteralPath $src -Destination $assetDebDir -Force
}

if ([string]::IsNullOrWhiteSpace($OutputZip)) {
  $OutputZip = Join-Path (Split-Path -Parent $skillRoot) "ddn-lustre-client-skill.zip"
}

$zipPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputZip)
if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}

Compress-Archive -Path (Join-Path $skillRoot "*") -DestinationPath $zipPath -Force
Write-Host "Created $zipPath"
