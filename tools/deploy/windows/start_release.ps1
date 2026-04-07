param(
  [string]$ReleaseRoot = "",
  [string]$ReleasesDir = "",
  [string]$Environment = "production",
  [string]$BashPath = "",
  [string[]]$PropaneArguments = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ArlenBashPath {
  param([string]$RequestedPath)

  $candidates = @()
  if ($RequestedPath) {
    $candidates += $RequestedPath
  }
  if ($env:ARLEN_BASH_PATH) {
    $candidates += $env:ARLEN_BASH_PATH
  }
  $candidates += @(
    "C:\msys64\usr\bin\bash.exe",
    "C:\Program Files\Git\bin\bash.exe"
  )

  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  throw "start_release.ps1: unable to locate bash.exe; set -BashPath or ARLEN_BASH_PATH"
}

function Quote-BashArgument {
  param([string]$Value)
  if ($null -eq $Value) {
    return "''"
  }
  return "'" + $Value.Replace("'", "'`"'`"'") + "'"
}

function Resolve-ActiveReleaseRoot {
  param(
    [string]$RequestedReleaseRoot,
    [string]$RequestedReleasesDir
  )

  if ($RequestedReleaseRoot) {
    return (Resolve-Path -LiteralPath $RequestedReleaseRoot).Path
  }

  if (-not $RequestedReleasesDir) {
    throw "start_release.ps1: set -ReleaseRoot or -ReleasesDir"
  }

  $resolvedReleasesDir = (Resolve-Path -LiteralPath $RequestedReleasesDir).Path
  $metadataPath = Join-Path $resolvedReleasesDir "current.release-id"
  if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
    throw "start_release.ps1: active release metadata not found: $metadataPath"
  }

  $releaseId = (Get-Content -LiteralPath $metadataPath -Raw).Trim()
  if (-not $releaseId) {
    throw "start_release.ps1: active release metadata is empty: $metadataPath"
  }

  $resolvedReleaseRoot = Join-Path $resolvedReleasesDir $releaseId
  if (-not (Test-Path -LiteralPath $resolvedReleaseRoot -PathType Container)) {
    throw "start_release.ps1: active release root not found: $resolvedReleaseRoot"
  }
  return $resolvedReleaseRoot
}

$resolvedReleaseRoot = Resolve-ActiveReleaseRoot -RequestedReleaseRoot $ReleaseRoot -RequestedReleasesDir $ReleasesDir
$appRoot = Join-Path $resolvedReleaseRoot "app"
$frameworkRoot = Join-Path $resolvedReleaseRoot "framework"
$propanePath = Join-Path $frameworkRoot "bin\propane"
$tmpRoot = Join-Path $appRoot "tmp"
$pidFile = Join-Path $tmpRoot "propane.pid"
$controlFile = Join-Path $tmpRoot "propane.control"

if (-not (Test-Path -LiteralPath $appRoot -PathType Container)) {
  throw "start_release.ps1: release app root not found: $appRoot"
}
if (-not (Test-Path -LiteralPath $frameworkRoot -PathType Container)) {
  throw "start_release.ps1: release framework root not found: $frameworkRoot"
}
if (-not (Test-Path -LiteralPath $propanePath -PathType Leaf)) {
  throw "start_release.ps1: propane launcher not found: $propanePath"
}

New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
$env:ARLEN_APP_ROOT = $appRoot
$env:ARLEN_FRAMEWORK_ROOT = $frameworkRoot
$env:ARLEN_PROPANE_CONTROL_FILE = $controlFile

$arguments = @(
  $propanePath,
  "--env",
  $Environment,
  "--pid-file",
  $pidFile
) + $PropaneArguments
$bashCommand = (($arguments | ForEach-Object { Quote-BashArgument $_ }) -join " ")

& (Resolve-ArlenBashPath $BashPath) -lc $bashCommand
exit $LASTEXITCODE
