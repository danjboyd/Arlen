param(
  [string]$ReleaseRoot = "",
  [string]$ReleasesDir = "",
  [ValidateSet("reload", "term", "stop", "shutdown", "int")]
  [string]$Action = "reload"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ActiveReleaseRoot {
  param(
    [string]$RequestedReleaseRoot,
    [string]$RequestedReleasesDir
  )

  if ($RequestedReleaseRoot) {
    return (Resolve-Path -LiteralPath $RequestedReleaseRoot).Path
  }

  if (-not $RequestedReleasesDir) {
    throw "send_release_control.ps1: set -ReleaseRoot or -ReleasesDir"
  }

  $resolvedReleasesDir = (Resolve-Path -LiteralPath $RequestedReleasesDir).Path
  $metadataPath = Join-Path $resolvedReleasesDir "current.release-id"
  if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
    throw "send_release_control.ps1: active release metadata not found: $metadataPath"
  }

  $releaseId = (Get-Content -LiteralPath $metadataPath -Raw).Trim()
  if (-not $releaseId) {
    throw "send_release_control.ps1: active release metadata is empty: $metadataPath"
  }

  $resolvedReleaseRoot = Join-Path $resolvedReleasesDir $releaseId
  if (-not (Test-Path -LiteralPath $resolvedReleaseRoot -PathType Container)) {
    throw "send_release_control.ps1: active release root not found: $resolvedReleaseRoot"
  }
  return $resolvedReleaseRoot
}

$resolvedReleaseRoot = Resolve-ActiveReleaseRoot -RequestedReleaseRoot $ReleaseRoot -RequestedReleasesDir $ReleasesDir
$controlFile = Join-Path $resolvedReleaseRoot "app\tmp\propane.control"

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $controlFile) | Out-Null
Set-Content -LiteralPath $controlFile -Value "$Action`n" -Encoding ascii -NoNewline
