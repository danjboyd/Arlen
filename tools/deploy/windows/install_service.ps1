param(
  [ValidateSet("dev", "runtime")]
  [string]$Mode = "",
  [string]$Name = "",
  [string]$AppRoot = "",
  [string]$ReleasesDir = "",
  [string]$LogDir = "",
  [string]$NSSMPath = "",
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
    "--log-dir" { $index++; if ($index -lt $args.Count) { $LogDir = [string]$args[$index] }; continue }
    "-LogDir" { $index++; if ($index -lt $args.Count) { $LogDir = [string]$args[$index] }; continue }
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
    @{
      version = "phase7g-agent-dx-contracts-v1"
      command = "service"
      workflow = "service.install"
      status = "error"
      exit_code = $ExitCode
      error = @{
        code = $Code
        message = $Message
      }
    } | ConvertTo-Json -Depth 6
  } else {
    Write-Error $Message
  }
  exit $ExitCode
}

function Convert-ToStablePath {
  param([string]$PathValue)
  if (-not $PathValue) {
    return ""
  }
  return (Resolve-Path -LiteralPath $PathValue).Path
}

function Test-ArlenAppRoot {
  param([string]$Candidate)

  if (-not $Candidate) {
    return $false
  }
  if (-not (Test-Path -LiteralPath $Candidate -PathType Container)) {
    return $false
  }
  if (-not (Test-Path -LiteralPath (Join-Path $Candidate "config\app.plist") -PathType Leaf)) {
    return $false
  }
  if (Test-Path -LiteralPath (Join-Path $Candidate "app_lite.m") -PathType Leaf) {
    return $true
  }
  return (Test-Path -LiteralPath (Join-Path $Candidate "src") -PathType Container)
}

function Find-ArlenAppRoot {
  param([string]$StartPath)

  $cursor = (Resolve-Path -LiteralPath $StartPath).Path
  while ($cursor) {
    if (Test-ArlenAppRoot $cursor) {
      return $cursor
    }
    $parent = Split-Path -Parent $cursor
    if (-not $parent -or $parent -eq $cursor) {
      break
    }
    $cursor = $parent
  }
  return ""
}

function Test-ArlenReleasesDir {
  param([string]$Candidate)

  if (-not $Candidate) {
    return $false
  }
  if (-not (Test-Path -LiteralPath $Candidate -PathType Container)) {
    return $false
  }
  return (Test-Path -LiteralPath (Join-Path $Candidate "current.release-id") -PathType Leaf)
}

function Find-ArlenReleasesDir {
  param([string]$StartPath)

  $cursor = (Resolve-Path -LiteralPath $StartPath).Path
  while ($cursor) {
    if (Test-ArlenReleasesDir $cursor) {
      return $cursor
    }
    $parent = Split-Path -Parent $cursor
    if (-not $parent -or $parent -eq $cursor) {
      break
    }
    $cursor = $parent
  }
  return ""
}

function Resolve-ArlenNSSMPath {
  param([string]$RequestedPath)

  $candidates = @()
  if ($RequestedPath) {
    $candidates += $RequestedPath
  }
  if ($env:ARLEN_NSSM_PATH) {
    $candidates += $env:ARLEN_NSSM_PATH
  }

  $command = Get-Command nssm.exe -ErrorAction SilentlyContinue
  if ($command) {
    $candidates += $command.Source
  }
  $command = Get-Command nssm -ErrorAction SilentlyContinue
  if ($command) {
    $candidates += $command.Source
  }

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

  Emit-ArlenServiceError "nssm_not_found" "arlen service install: NSSM was not found. Install `NSSM.NSSM` via `winget install NSSM.NSSM` or set ARLEN_NSSM_PATH."
}

function Resolve-FrameworkRoot {
  return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..\..")).Path
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
  Emit-ArlenServiceError "powershell_not_found" "arlen service install: unable to locate powershell.exe"
}

function Resolve-ActiveReleaseRoot {
  param([string]$ResolvedReleasesDir)

  $metadataPath = Join-Path $ResolvedReleasesDir "current.release-id"
  $releaseId = (Get-Content -LiteralPath $metadataPath -Raw).Trim()
  if (-not $releaseId) {
    Emit-ArlenServiceError "empty_release_id" "arlen service install: active release metadata is empty: $metadataPath"
  }
  $releaseRoot = Join-Path $ResolvedReleasesDir $releaseId
  if (-not (Test-Path -LiteralPath $releaseRoot -PathType Container)) {
    Emit-ArlenServiceError "release_root_missing" "arlen service install: active release root not found: $releaseRoot"
  }
  return (Resolve-Path -LiteralPath $releaseRoot).Path
}

function Get-DefaultServiceName {
  param(
    [string]$SelectedMode,
    [string]$ResolvedAppRoot,
    [string]$ResolvedReleasesDir
  )

  $baseName = if ($SelectedMode -eq "dev") {
    Split-Path -Leaf $ResolvedAppRoot
  } else {
    Split-Path -Leaf (Split-Path -Parent $ResolvedReleasesDir)
  }
  $safe = ($baseName -replace "[^A-Za-z0-9_-]", "-").Trim("-")
  if (-not $safe) {
    $safe = "app"
  }
  if ($SelectedMode -eq "dev") {
    return "arlen-dev-$safe"
  }
  return "arlen-$safe"
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
    Emit-ArlenServiceError $ErrorCode "arlen service install: $ActionDescription failed. $detail"
  }
}

if (-not $Mode) {
  Emit-ArlenServiceError "missing_mode" "arlen service install: --mode dev|runtime is required" 2
}

$frameworkRoot = Resolve-FrameworkRoot
$workingDirectory = (Get-Location).Path
$resolvedAppRoot = ""
$resolvedReleasesDir = ""
$resolvedReleaseRoot = ""

if ($Mode -eq "dev") {
  if ($AppRoot) {
    if (-not (Test-ArlenAppRoot $AppRoot)) {
      Emit-ArlenServiceError "invalid_app_root" "arlen service install: --app-root is not a supported Arlen app root: $AppRoot"
    }
    $resolvedAppRoot = (Resolve-Path -LiteralPath $AppRoot).Path
  } else {
    $resolvedAppRoot = Find-ArlenAppRoot $workingDirectory
    if (-not $resolvedAppRoot) {
      Emit-ArlenServiceError "app_root_unresolved" "arlen service install: could not auto-discover app root from $workingDirectory"
    }
  }
} else {
  if ($ReleasesDir) {
    if (-not (Test-ArlenReleasesDir $ReleasesDir)) {
      Emit-ArlenServiceError "invalid_releases_dir" "arlen service install: --releases-dir does not point to a releases directory: $ReleasesDir"
    }
    $resolvedReleasesDir = (Resolve-Path -LiteralPath $ReleasesDir).Path
  } else {
    $resolvedReleasesDir = Find-ArlenReleasesDir $workingDirectory
    if (-not $resolvedReleasesDir) {
      Emit-ArlenServiceError "releases_dir_unresolved" "arlen service install: could not auto-discover releases directory from $workingDirectory"
    }
  }
  $resolvedReleaseRoot = Resolve-ActiveReleaseRoot $resolvedReleasesDir
}

$serviceName = if ($Name) { $Name } else { Get-DefaultServiceName -SelectedMode $Mode -ResolvedAppRoot $resolvedAppRoot -ResolvedReleasesDir $resolvedReleasesDir }
$serviceName = ($serviceName -replace "[^A-Za-z0-9_-]", "-").Trim("-")
if (-not $serviceName) {
  Emit-ArlenServiceError "invalid_service_name" "arlen service install: service name resolved to empty output"
}

$resolvedLogDir = if ($LogDir) {
  [System.IO.Path]::GetFullPath($LogDir)
} elseif ($Mode -eq "dev") {
  Join-Path $resolvedAppRoot "tmp\service"
} else {
  Join-Path $resolvedReleasesDir "service"
}

$stdoutLog = Join-Path $resolvedLogDir ($(if ($Mode -eq "dev") { "boomhauer.stdout.log" } else { "propane.stdout.log" }))
$stderrLog = Join-Path $resolvedLogDir ($(if ($Mode -eq "dev") { "boomhauer.stderr.log" } else { "propane.stderr.log" }))
$powerShellPath = Resolve-PowerShellPath
$nssmPath = ""

if ($Mode -eq "dev") {
  $launcherPath = Join-Path $frameworkRoot "bin\boomhauer.ps1"
  $appDirectory = $resolvedAppRoot
  $appParameters = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $launcherPath
  )
  $environmentLines = @(
    "ARLEN_APP_ROOT=$resolvedAppRoot",
    "ARLEN_FRAMEWORK_ROOT=$frameworkRoot"
  )
  if ($env:ARLEN_BASH_PATH) {
    $environmentLines += "ARLEN_BASH_PATH=$($env:ARLEN_BASH_PATH)"
  }
  $description = "Arlen development service (boomhauer) for $resolvedAppRoot"
} else {
  $launcherPath = Join-Path $frameworkRoot "tools\deploy\windows\start_release.ps1"
  $appDirectory = $resolvedReleasesDir
  $appParameters = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $launcherPath,
    "-ReleasesDir",
    $resolvedReleasesDir
  )
  $environmentLines = @()
  if ($env:ARLEN_BASH_PATH) {
    $environmentLines += "ARLEN_BASH_PATH=$($env:ARLEN_BASH_PATH)"
  }
  $description = "Arlen runtime service (propane) for $resolvedReleasesDir"
}

$plan = @{
  version = "phase7g-agent-dx-contracts-v1"
  command = "service"
  workflow = "service.install"
  status = if ($DryRun) { "planned" } else { "ok" }
  mode = $Mode
  name = $serviceName
  framework_root = $frameworkRoot
  app_root = $resolvedAppRoot
  releases_dir = $resolvedReleasesDir
  release_root = $resolvedReleaseRoot
  log_dir = $resolvedLogDir
  stdout_log = $stdoutLog
  stderr_log = $stderrLog
  service_backend = "nssm"
  executable = $powerShellPath
  executable_args = $appParameters
  app_directory = $appDirectory
  environment = $environmentLines
}

if ($DryRun) {
  if ($Json) {
    $plan | ConvertTo-Json -Depth 8
  } else {
    Write-Host "arlen service install dry-run"
    Write-Host "  mode: $Mode"
    Write-Host "  name: $serviceName"
    Write-Host "  backend: NSSM"
    Write-Host "  app directory: $appDirectory"
    Write-Host "  logs: $stdoutLog / $stderrLog"
  }
  exit 0
}

if (-not (Test-IsElevated)) {
  Emit-ArlenServiceError "elevation_required" "arlen service install: administrator access is required to register a Windows service. Re-run from an elevated PowerShell session."
}

$nssmPath = Resolve-ArlenNSSMPath $NSSMPath
New-Item -ItemType Directory -Force -Path $resolvedLogDir | Out-Null

Invoke-NSSM -ExecutablePath $nssmPath -Arguments @("install", $serviceName, $powerShellPath) + $appParameters -ErrorCode "service_install_failed" -ActionDescription "installing service $serviceName"
Invoke-NSSM -ExecutablePath $nssmPath -Arguments @("set", $serviceName, "AppDirectory", $appDirectory) -ErrorCode "service_config_failed" -ActionDescription "setting AppDirectory for $serviceName"
Invoke-NSSM -ExecutablePath $nssmPath -Arguments @("set", $serviceName, "AppStdout", $stdoutLog) -ErrorCode "service_config_failed" -ActionDescription "setting AppStdout for $serviceName"
Invoke-NSSM -ExecutablePath $nssmPath -Arguments @("set", $serviceName, "AppStderr", $stderrLog) -ErrorCode "service_config_failed" -ActionDescription "setting AppStderr for $serviceName"
Invoke-NSSM -ExecutablePath $nssmPath -Arguments @("set", $serviceName, "AppRotateFiles", "1") -ErrorCode "service_config_failed" -ActionDescription "setting AppRotateFiles for $serviceName"
Invoke-NSSM -ExecutablePath $nssmPath -Arguments @("set", $serviceName, "Start", "SERVICE_AUTO_START") -ErrorCode "service_config_failed" -ActionDescription "setting Start for $serviceName"
Invoke-NSSM -ExecutablePath $nssmPath -Arguments @("set", $serviceName, "AppExit", "Default", "Restart") -ErrorCode "service_config_failed" -ActionDescription "setting AppExit for $serviceName"
Invoke-NSSM -ExecutablePath $nssmPath -Arguments @("set", $serviceName, "Description", $description) -ErrorCode "service_config_failed" -ActionDescription "setting Description for $serviceName"
if ($environmentLines.Count -gt 0) {
  Invoke-NSSM -ExecutablePath $nssmPath -Arguments (@("set", $serviceName, "AppEnvironmentExtra") + $environmentLines) -ErrorCode "service_config_failed" -ActionDescription "setting AppEnvironmentExtra for $serviceName"
}

if ($Json) {
  $plan | ConvertTo-Json -Depth 8
} else {
  Write-Host "Installed Arlen service $serviceName"
  Write-Host "  mode: $Mode"
  Write-Host "  stdout log: $stdoutLog"
  Write-Host "  stderr log: $stderrLog"
}
