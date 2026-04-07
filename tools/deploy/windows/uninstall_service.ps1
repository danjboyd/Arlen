param(
  [ValidateSet("dev", "runtime")]
  [string]$Mode = "",
  [string]$Name = "",
  [string]$AppRoot = "",
  [string]$ReleasesDir = "",
  [string]$NSSMPath = "",
  [string]$ResultFile = "",
  [switch]$DryRun,
  [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

for ($index = 0; $index -lt $args.Count; $index++) {
  $token = [string]$args[$index]
  switch ($token) {
    "--mode" { $index++; if ($index -lt $args.Count) { $Mode = [string]$args[$index] }; continue }
    "-Mode" { $index++; if ($index -lt $args.Count) { $Mode = [string]$args[$index] }; continue }
    "--name" { $index++; if ($index -lt $args.Count) { $Name = [string]$args[$index] }; continue }
    "-Name" { $index++; if ($index -lt $args.Count) { $Name = [string]$args[$index] }; continue }
    "--app-root" { $index++; if ($index -lt $args.Count) { $AppRoot = [string]$args[$index] }; continue }
    "-AppRoot" { $index++; if ($index -lt $args.Count) { $AppRoot = [string]$args[$index] }; continue }
    "--releases-dir" { $index++; if ($index -lt $args.Count) { $ReleasesDir = [string]$args[$index] }; continue }
    "-ReleasesDir" { $index++; if ($index -lt $args.Count) { $ReleasesDir = [string]$args[$index] }; continue }
    "--nssm-path" { $index++; if ($index -lt $args.Count) { $NSSMPath = [string]$args[$index] }; continue }
    "-NSSMPath" { $index++; if ($index -lt $args.Count) { $NSSMPath = [string]$args[$index] }; continue }
    "--dry-run" { $DryRun = $true; continue }
    "-DryRun" { $DryRun = $true; continue }
    "--json" { $Json = $true; continue }
    "-Json" { $Json = $true; continue }
  }
}

function Emit-ArlenServiceError {
  param(
    [string]$Code,
    [string]$Message,
    [int]$ExitCode = 1
  )

  if ($Json) {
    $payload = @{
      version = "phase7g-agent-dx-contracts-v1"
      command = "service"
      workflow = "service.uninstall"
      status = "error"
      exit_code = $ExitCode
      error = @{
        code = $Code
        message = $Message
      }
    }
    $json = $payload | ConvertTo-Json -Depth 6
    if ($ResultFile) {
      Set-Content -LiteralPath $ResultFile -Value $json -Encoding UTF8
    }
    $json
  } else {
    Write-Error $Message
  }
  exit $ExitCode
}

function Write-ArlenServicePayload {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Payload
  )

  if ($Json) {
    $json = $Payload | ConvertTo-Json -Depth 6
    if ($ResultFile) {
      Set-Content -LiteralPath $ResultFile -Value $json -Encoding UTF8
    }
    $json
  } else {
    return $false
  }
  return $true
}

function Test-ArlenAppRoot {
  param([string]$Candidate)
  if (-not $Candidate) { return $false }
  if (-not (Test-Path -LiteralPath $Candidate -PathType Container)) { return $false }
  if (-not (Test-Path -LiteralPath (Join-Path $Candidate "config\app.plist") -PathType Leaf)) { return $false }
  if (Test-Path -LiteralPath (Join-Path $Candidate "app_lite.m") -PathType Leaf) { return $true }
  return (Test-Path -LiteralPath (Join-Path $Candidate "src") -PathType Container)
}

function Find-ArlenAppRoot {
  param([string]$StartPath)
  $cursor = (Resolve-Path -LiteralPath $StartPath).Path
  while ($cursor) {
    if (Test-ArlenAppRoot $cursor) { return $cursor }
    $parent = Split-Path -Parent $cursor
    if (-not $parent -or $parent -eq $cursor) { break }
    $cursor = $parent
  }
  return ""
}

function Test-ArlenReleasesDir {
  param([string]$Candidate)
  if (-not $Candidate) { return $false }
  if (-not (Test-Path -LiteralPath $Candidate -PathType Container)) { return $false }
  return (Test-Path -LiteralPath (Join-Path $Candidate "current.release-id") -PathType Leaf)
}

function Find-ArlenReleasesDir {
  param([string]$StartPath)
  $cursor = (Resolve-Path -LiteralPath $StartPath).Path
  while ($cursor) {
    if (Test-ArlenReleasesDir $cursor) { return $cursor }
    $parent = Split-Path -Parent $cursor
    if (-not $parent -or $parent -eq $cursor) { break }
    $cursor = $parent
  }
  return ""
}

function Resolve-ArlenNSSMPath {
  param([string]$RequestedPath)
  $candidates = @()
  if ($RequestedPath) { $candidates += $RequestedPath }
  if ($env:ARLEN_NSSM_PATH) { $candidates += $env:ARLEN_NSSM_PATH }
  $command = Get-Command nssm.exe -ErrorAction SilentlyContinue
  if ($command) { $candidates += $command.Source }
  $command = Get-Command nssm -ErrorAction SilentlyContinue
  if ($command) { $candidates += $command.Source }
  $candidates += @(
    "C:\Program Files\NSSM\win64\nssm.exe",
    "C:\Program Files\nssm\win64\nssm.exe",
    (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\nssm.exe")
  )
  $wingetPackageRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
  if (Test-Path -LiteralPath $wingetPackageRoot -PathType Container) {
    $wingetCandidates = Get-ChildItem -Path $wingetPackageRoot -Filter nssm.exe -Recurse -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending
    foreach ($wingetCandidate in $wingetCandidates) {
      if ($wingetCandidate -and $wingetCandidate.FullName) {
        $candidates += $wingetCandidate.FullName
      }
    }
  }
  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  Emit-ArlenServiceError "nssm_not_found" "arlen service uninstall: NSSM was not found. Install `NSSM.NSSM` via `winget install NSSM.NSSM` or set ARLEN_NSSM_PATH."
}

function Get-DefaultServiceName {
  param([string]$SelectedMode, [string]$ResolvedAppRoot, [string]$ResolvedReleasesDir)
  $baseName = if ($SelectedMode -eq "dev") {
    Split-Path -Leaf $ResolvedAppRoot
  } else {
    Split-Path -Leaf (Split-Path -Parent $ResolvedReleasesDir)
  }
  $safe = ($baseName -replace "[^A-Za-z0-9_-]", "-").Trim("-")
  if (-not $safe) { $safe = "app" }
  if ($SelectedMode -eq "dev") { return "arlen-dev-$safe" }
  return "arlen-$safe"
}

function Test-IsElevated {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-PowerShellPath {
  $candidates = @(
    "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
    "C:\Program Files\PowerShell\7\pwsh.exe"
  )
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  Emit-ArlenServiceError "powershell_not_found" "arlen service uninstall: unable to locate powershell.exe"
}

function Invoke-ArlenServiceElevation {
  param(
    [string]$SelectedMode,
    [string]$SelectedName,
    [string]$SelectedAppRoot,
    [string]$SelectedReleasesDir,
    [string]$SelectedNSSMPath
  )

  $powerShellPath = Resolve-PowerShellPath
  $scriptPath = (Resolve-Path -LiteralPath $PSCommandPath).Path
  $workingDirectory = (Get-Location).Path
  $resultFilePath = ""
  if ($Json) {
    $resultFilePath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString() + ".json")
  }

  $elevatedArgs = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $scriptPath,
    "-Mode",
    $SelectedMode
  )
  if ($SelectedName) { $elevatedArgs += @("-Name", $SelectedName) }
  if ($SelectedAppRoot) { $elevatedArgs += @("-AppRoot", $SelectedAppRoot) }
  if ($SelectedReleasesDir) { $elevatedArgs += @("-ReleasesDir", $SelectedReleasesDir) }
  if ($SelectedNSSMPath) { $elevatedArgs += @("-NSSMPath", $SelectedNSSMPath) }
  if ($Json) {
    $elevatedArgs += "-Json"
    $elevatedArgs += @("-ResultFile", $resultFilePath)
  }

  try {
    $process = Start-Process -FilePath $powerShellPath `
                             -ArgumentList $elevatedArgs `
                             -Verb RunAs `
                             -WorkingDirectory $workingDirectory `
                             -Wait `
                             -PassThru
  } catch {
    Emit-ArlenServiceError "uac_cancelled" "arlen service uninstall: elevation was cancelled or denied."
  }

  if ($Json -and $resultFilePath -and (Test-Path -LiteralPath $resultFilePath -PathType Leaf)) {
    try {
      $json = Get-Content -LiteralPath $resultFilePath -Raw
      if ($json) {
        Write-Output $json.Trim()
      }
    } finally {
      Remove-Item -LiteralPath $resultFilePath -Force -ErrorAction SilentlyContinue
    }
  }

  exit $process.ExitCode
}

function Invoke-NSSM {
  param(
    [string]$ExecutablePath,
    [string[]]$Arguments,
    [string]$ErrorCode,
    [string]$ActionDescription
  )

  $output = & $ExecutablePath @Arguments 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) {
    $detail = if ($null -ne $output) { $output.Trim() } else { "" }
    if (-not $detail) {
      $detail = "nssm exited with code $LASTEXITCODE"
    }
    Emit-ArlenServiceError $ErrorCode "arlen service uninstall: $ActionDescription failed. $detail"
  }
}

if (-not $Mode) {
  Emit-ArlenServiceError "missing_mode" "arlen service uninstall: --mode dev|runtime is required" 2
}

$workingDirectory = (Get-Location).Path
$resolvedAppRoot = ""
$resolvedReleasesDir = ""
if ($Mode -eq "dev") {
  if ($AppRoot) {
    if (-not (Test-ArlenAppRoot $AppRoot)) {
      Emit-ArlenServiceError "invalid_app_root" "arlen service uninstall: --app-root is not a supported Arlen app root: $AppRoot"
    }
    $resolvedAppRoot = (Resolve-Path -LiteralPath $AppRoot).Path
  } else {
    $resolvedAppRoot = Find-ArlenAppRoot $workingDirectory
    if (-not $resolvedAppRoot) {
      Emit-ArlenServiceError "app_root_unresolved" "arlen service uninstall: could not auto-discover app root from $workingDirectory"
    }
  }
} else {
  if ($ReleasesDir) {
    if (-not (Test-ArlenReleasesDir $ReleasesDir)) {
      Emit-ArlenServiceError "invalid_releases_dir" "arlen service uninstall: --releases-dir does not point to a releases directory: $ReleasesDir"
    }
    $resolvedReleasesDir = (Resolve-Path -LiteralPath $ReleasesDir).Path
  } else {
    $resolvedReleasesDir = Find-ArlenReleasesDir $workingDirectory
    if (-not $resolvedReleasesDir) {
      Emit-ArlenServiceError "releases_dir_unresolved" "arlen service uninstall: could not auto-discover releases directory from $workingDirectory"
    }
  }
}

$serviceName = if ($Name) { $Name } else { Get-DefaultServiceName -SelectedMode $Mode -ResolvedAppRoot $resolvedAppRoot -ResolvedReleasesDir $resolvedReleasesDir }
$serviceName = ($serviceName -replace "[^A-Za-z0-9_-]", "-").Trim("-")
if (-not $serviceName) {
  Emit-ArlenServiceError "invalid_service_name" "arlen service uninstall: service name resolved to empty output"
}

$plan = @{
  version = "phase7g-agent-dx-contracts-v1"
  command = "service"
  workflow = "service.uninstall"
  status = if ($DryRun) { "planned" } else { "ok" }
  mode = $Mode
  name = $serviceName
  service_backend = "nssm"
  app_root = $resolvedAppRoot
  releases_dir = $resolvedReleasesDir
}

if ($DryRun) {
  if (-not (Write-ArlenServicePayload -Payload $plan)) {
    Write-Host "arlen service uninstall dry-run"
    Write-Host "  mode: $Mode"
    Write-Host "  name: $serviceName"
  }
  exit 0
}

if (-not (Test-IsElevated)) {
  Invoke-ArlenServiceElevation -SelectedMode $Mode `
                               -SelectedName $serviceName `
                               -SelectedAppRoot $resolvedAppRoot `
                               -SelectedReleasesDir $resolvedReleasesDir `
                               -SelectedNSSMPath $NSSMPath
}

$nssmPath = Resolve-ArlenNSSMPath $NSSMPath
Invoke-NSSM -ExecutablePath $nssmPath -Arguments @("stop", $serviceName) -ErrorCode "service_stop_failed" -ActionDescription "stopping service $serviceName"
Invoke-NSSM -ExecutablePath $nssmPath -Arguments @("remove", $serviceName, "confirm") -ErrorCode "service_remove_failed" -ActionDescription "removing service $serviceName"

if (-not (Write-ArlenServicePayload -Payload $plan)) {
  Write-Host "Uninstalled Arlen service $serviceName"
}
