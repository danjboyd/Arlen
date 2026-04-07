param(
  [string]$ReleaseRoot = "",
  [string]$ReleasesDir = "",
  [string]$Environment = "production",
  [string]$BashPath = "",
  [string[]]$MigrateArguments = @()
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

  throw "invoke_release_migrate.ps1: unable to locate bash.exe; set -BashPath or ARLEN_BASH_PATH"
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
    throw "invoke_release_migrate.ps1: set -ReleaseRoot or -ReleasesDir"
  }

  $resolvedReleasesDir = (Resolve-Path -LiteralPath $RequestedReleasesDir).Path
  $metadataPath = Join-Path $resolvedReleasesDir "current.release-id"
  if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
    throw "invoke_release_migrate.ps1: active release metadata not found: $metadataPath"
  }

  $releaseId = (Get-Content -LiteralPath $metadataPath -Raw).Trim()
  if (-not $releaseId) {
    throw "invoke_release_migrate.ps1: active release metadata is empty: $metadataPath"
  }

  $resolvedReleaseRoot = Join-Path $resolvedReleasesDir $releaseId
  if (-not (Test-Path -LiteralPath $resolvedReleaseRoot -PathType Container)) {
    throw "invoke_release_migrate.ps1: active release root not found: $resolvedReleaseRoot"
  }
  return $resolvedReleaseRoot
}

$resolvedReleaseRoot = Resolve-ActiveReleaseRoot -RequestedReleaseRoot $ReleaseRoot -RequestedReleasesDir $ReleasesDir
$appRoot = Join-Path $resolvedReleaseRoot "app"
$frameworkRoot = Join-Path $resolvedReleaseRoot "framework"
$arlenPath = Join-Path $frameworkRoot "bin\arlen"

if (-not (Test-Path -LiteralPath $appRoot -PathType Container)) {
  throw "invoke_release_migrate.ps1: release app root not found: $appRoot"
}
if (-not (Test-Path -LiteralPath $frameworkRoot -PathType Container)) {
  throw "invoke_release_migrate.ps1: release framework root not found: $frameworkRoot"
}
if (-not (Test-Path -LiteralPath $arlenPath -PathType Leaf)) {
  throw "invoke_release_migrate.ps1: arlen launcher not found: $arlenPath"
}

$env:ARLEN_APP_ROOT = $appRoot
$env:ARLEN_FRAMEWORK_ROOT = $frameworkRoot

$arguments = @(
  $arlenPath,
  "migrate",
  "--env",
  $Environment
) + $MigrateArguments
$bashCommand = "cd " + (Quote-BashArgument $appRoot) + " && " + (($arguments | ForEach-Object { Quote-BashArgument $_ }) -join " ")

& (Resolve-ArlenBashPath $BashPath) -lc $bashCommand
exit $LASTEXITCODE
