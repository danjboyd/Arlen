Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-ToArlenMsysPath {
  param([Parameter(Mandatory = $true)][string]$WindowsPath)

  $resolved = [System.IO.Path]::GetFullPath($WindowsPath)
  $normalized = $resolved -replace "\\", "/"
  if ($normalized -match "^([A-Za-z]):(/.*)?$") {
    $drive = $Matches[1].ToLowerInvariant()
    $rest = if ($Matches[2]) { $Matches[2] } else { "" }
    return "/$drive$rest"
  }

  throw "Unable to convert Windows path to MSYS2 path: $WindowsPath"
}

function Resolve-ArlenMsysRoot {
  $candidates = @()
  if ($env:ARLEN_MSYS_ROOT) {
    $candidates += $env:ARLEN_MSYS_ROOT
  }
  $candidates += "C:\msys64"

  foreach ($candidate in $candidates) {
    if (-not $candidate) {
      continue
    }
    $envExe = Join-Path $candidate "usr\bin\env.exe"
    $gnuStepSh = Join-Path $candidate "clang64\share\GNUstep\Makefiles\GNUstep.sh"
    if ((Test-Path -LiteralPath $envExe) -and (Test-Path -LiteralPath $gnuStepSh)) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  throw "MSYS2 CLANG64 root not found. Install MSYS2 under C:\msys64 or set ARLEN_MSYS_ROOT."
}

function Invoke-ArlenClang64Command {
  param(
    [Parameter(Mandatory = $true)][string]$LauncherPath,
    [string[]]$CommandArguments = @()
  )

  $resolvedLauncherPath = (Resolve-Path -LiteralPath $LauncherPath).Path
  $workingDirectory = (Get-Location).Path
  $msysRoot = Resolve-ArlenMsysRoot
  $envExe = Join-Path $msysRoot "usr\bin\env.exe"
  $gnuStepSh = Join-Path $msysRoot "clang64\share\GNUstep\Makefiles\GNUstep.sh"
  $workingDirectoryMsys = Convert-ToArlenMsysPath -WindowsPath $workingDirectory
  $launcherPathMsys = Convert-ToArlenMsysPath -WindowsPath $resolvedLauncherPath

  $bootstrap = @"
source /etc/profile
export MSYSTEM=CLANG64
export CHERE_INVOKING=1
export PATH=/clang64/bin:/usr/bin:`$PATH
export CC=clang
export CXX=clang++
export GNUSTEP_CONFIG_FILE=/clang64/etc/GNUstep/GNUstep.conf
export GNUSTEP_MAKEFILES=/clang64/share/GNUstep/Makefiles
export GNUSTEP_SYSTEM_ROOT=/clang64
source /clang64/share/GNUstep/Makefiles/GNUstep.sh
working_dir="`$1"
launcher="`$2"
shift 2
cd "`$working_dir"
exec "`$launcher" "`$@"
"@

  & $envExe 'MSYSTEM=CLANG64' 'CHERE_INVOKING=1' '/usr/bin/bash' '-lc' $bootstrap 'arlen-windows-wrapper' $workingDirectoryMsys $launcherPathMsys @CommandArguments
  return $LASTEXITCODE
}
