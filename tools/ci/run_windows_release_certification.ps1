<#
Certify an arlen-X.Y.Z-windows-x64.zip the way a user installs it: install it
with tools/install.ps1, then run `arlen new`, build the app with `arlen
boomhauer --prepare-only`, and serve it with `arlen boomhauer`, all through the
installed arlen.cmd launcher from PowerShell. The server must answer /healthz
and /, and the prebuilt framework must not be rebuilt.

  powershell -ExecutionPolicy Bypass -File tools\ci\run_windows_release_certification.ps1 -Archive build\release-assets\arlen-X.Y.Z-windows-x64.zip

Runs outside the MSYS2 shell, as a user would. The gnustep-cli managed CLANG64
root must already be installed (install.ps1 finds it). Writes a summary to
build\release_confidence\windows\summary.json.
#>
param(
  [Parameter(Mandatory = $true)][string]$Archive,
  [string]$WorkDir = "",
  [switch]$KeepWorkDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
. (Join-Path $PSScriptRoot 'windows_installer_test_lock.ps1')
$installerTestLock = Enter-ArlenInstallerTestLock
$savedUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$savedProcessPath = $env:Path

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Archive = (Resolve-Path -LiteralPath $Archive).Path
if (-not $WorkDir) {
  $base = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
  $WorkDir = Join-Path $base ("arlen-win-cert-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
}
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$prefix = Join-Path $WorkDir "Arlen"
$binDir = Join-Path $prefix "bin"
$appsDir = Join-Path $WorkDir "apps"
New-Item -ItemType Directory -Force -Path $appsDir | Out-Null
$summaryDir = Join-Path $repoRoot "build\release_confidence\windows"
New-Item -ItemType Directory -Force -Path $summaryDir | Out-Null

$steps = New-Object System.Collections.ArrayList
$server = $null

function Say([string]$Message) { Write-Host "windows-release-certification: $Message" }

function Write-Summary([string]$Status) {
  $summary = [ordered]@{
    version = "windows-release-certification-v1"
    status = $Status
    archive = [IO.Path]::GetFileName($Archive)
    steps = @($steps)
  }
  # UTF-8 without the BOM that Set-Content -Encoding UTF8 writes on 5.1.
  [IO.File]::WriteAllText((Join-Path $summaryDir "summary.json"), ($summary | ConvertTo-Json -Depth 4))
}

# Runs a step and records it; a failing step stops the run.
function Step([string]$Name, [scriptblock]$Body) {
  Say "== $Name"
  $started = Get-Date
  try {
    & $Body
    [void]$steps.Add([ordered]@{ name = $Name; status = "pass"; seconds = [int]((Get-Date) - $started).TotalSeconds })
  } catch {
    [void]$steps.Add([ordered]@{ name = $Name; status = "fail"; seconds = [int]((Get-Date) - $started).TotalSeconds; error = "$_" })
    throw
  }
}

# Runs arlen.cmd with output shown, and fails on a nonzero exit.
function Invoke-Arlen([string[]]$Arguments) {
  & arlen @Arguments
  if ($LASTEXITCODE -ne 0) { throw "arlen $($Arguments -join ' ') exited $LASTEXITCODE" }
}

function Stop-ServerTree {
  if ($script:server -and -not $script:server.HasExited) {
    # The launcher's children (env.exe, bash, boomhauer-app.exe) are separate
    # Windows processes, so end the whole tree.
    & taskkill /F /T /PID $script:server.Id 2>&1 | Out-Null
    Start-Sleep -Seconds 1
  }
}

try {
  Step "install" {
    & (Join-Path $repoRoot "tools\install.ps1") -Archive $Archive -Prefix $prefix -BinDir $binDir
    $script:arlenCmd = Join-Path $binDir "arlen.cmd"
    if (-not (Test-Path -LiteralPath $script:arlenCmd)) { throw "install.ps1 did not create $script:arlenCmd" }
    if (-not (Test-Path -LiteralPath (Join-Path $prefix "current\build\.release-prebuilt"))) {
      throw "the installed release has no build\.release-prebuilt"
    }
  }

  Push-Location $appsDir
  try {
    Step "bare arlen current shell" {
      if ((Get-Command arlen).Source -ne $script:arlenCmd) { throw 'bare arlen resolved outside the new install' }
      Invoke-Arlen @('doctor')
    }
    Step "bare arlen fresh shell from saved PATH" {
      $freshScript = Join-Path $WorkDir 'fresh-shell.ps1'
      $freshBody = @'
$ErrorActionPreference = 'Stop'
# Construct a fresh login environment, rather than inheriting the installer's
# process PATH. This verifies the persisted user PATH from outside checkout.
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine')
& arlen doctor
exit $LASTEXITCODE
'@
      [IO.File]::WriteAllText($freshScript, $freshBody)
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $freshScript
      if ($LASTEXITCODE -ne 0) { throw 'fresh shell could not run bare arlen doctor' }
    }
    Step "arlen new" { Invoke-Arlen @("new", "CertApp") }
  } finally {
    Pop-Location
  }
  $appRoot = Join-Path $appsDir "CertApp"

  Push-Location $appRoot
  try {
    # `arlen build` builds the framework; apps build through boomhauer.
    Step "app build" {
      # PS5.1 turns redirected native stderr into ErrorRecords, even for a
      # successful command (e.g. the whitespace-alias notice). Judge the exit.
      $savedPreference = $ErrorActionPreference
      try {
        $ErrorActionPreference = 'Continue'
        $output = & arlen boomhauer --prepare-only 2>&1 | Out-String
        $buildExit = $LASTEXITCODE
      } finally { $ErrorActionPreference = $savedPreference }
      Write-Host $output
      if ($buildExit -ne 0) { throw "arlen boomhauer --prepare-only exited $buildExit" }
      if ($output -match "building framework artifacts|rebuilding clean framework artifacts") {
        throw "boomhauer rebuilt the prebuilt framework"
      }
    }

    Step "arlen boomhauer" {
      $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
      $listener.Start()
      $port = $listener.LocalEndpoint.Port
      $listener.Stop()
      $log = Join-Path $WorkDir "boomhauer.log"
      $script:server = Start-Process -FilePath $script:arlenCmd -ArgumentList @("boomhauer", "--port", "$port") `
        -WorkingDirectory $appRoot -RedirectStandardOutput $log -RedirectStandardError "$log.err" `
        -NoNewWindow -PassThru
      $healthy = $false
      for ($i = 0; $i -lt 300; $i++) {
        try {
          $health = Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Uri "http://127.0.0.1:$port/healthz"
          if ($health.StatusCode -eq 200) { $healthy = $true; break }
        } catch {
        }
        if ($script:server.HasExited) { break }
        Start-Sleep -Seconds 1
      }
      if (-not $healthy) {
        Get-Content -LiteralPath $log, "$log.err" -ErrorAction SilentlyContinue | Write-Host
        throw "boomhauer never served /healthz on port $port"
      }
      $root = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 -Uri "http://127.0.0.1:$port/"
      if ($root.StatusCode -ne 200) { throw "GET / returned $($root.StatusCode)" }
      Say "boomhauer served /healthz and / on port $port"
    }
  } finally {
    Stop-ServerTree
    Pop-Location
  }

  Write-Summary "pass"
  Say "passed"
} catch {
  Stop-ServerTree
  Write-Summary "fail"
  Say "FAILED: $_"
  exit 1
} finally {
  $env:Path = $savedProcessPath
  [Environment]::SetEnvironmentVariable('Path', $savedUserPath, 'User')
  $installerTestLock.ReleaseMutex()
  $installerTestLock.Dispose()
  if (-not $KeepWorkDir) {
    $resolvedWork = [IO.Path]::GetFullPath($WorkDir)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedWork.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
      $current = Join-Path $resolvedWork 'Arlen\current'
      if ((Test-Path -LiteralPath $current) -and (Get-Item -LiteralPath $current -Force).LinkType -eq 'Junction') { [IO.Directory]::Delete($current) }
      Remove-Item -LiteralPath $resolvedWork -Recurse -Force -ErrorAction SilentlyContinue
    } else { Say "retaining non-temporary work directory $resolvedWork" }
  }
}
