param(
  [string]$InnerCommand = "",
  [string]$WorkingDirectory = (Join-Path $PSScriptRoot ".."),
  # Empty means auto-detect: ARLEN_MSYS_ROOT, then the gnustep-cli managed
  # toolchain (user, then system install), then a stock MSYS2 at C:\msys64.
  [string]$MsysRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-MsysRoot {
  param([string]$Requested)

  if (-not [string]::IsNullOrWhiteSpace($Requested)) {
    return $Requested
  }
  $candidates = @()
  if ($env:ARLEN_MSYS_ROOT) { $candidates += $env:ARLEN_MSYS_ROOT }
  if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA "gnustep-cli") }
  if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles "gnustep-cli") }
  $candidates += "C:\msys64"
  foreach ($candidate in $candidates) {
    if ((Test-Path (Join-Path $candidate "usr\bin\env.exe")) -and
        (Test-Path (Join-Path $candidate "clang64\share\GNUstep\Makefiles\GNUstep.sh"))) {
      return $candidate
    }
  }
  throw "No MSYS2 CLANG64 GNUstep root found (tried: $([string]::Join(', ', $candidates))). Install one with the gnustep-cli bootstrap or pass -MsysRoot."
}

$MsysRoot = Resolve-MsysRoot -Requested $MsysRoot
$envExe = Join-Path $MsysRoot "usr\\bin\\env.exe"
$gnuStepSh = Join-Path $MsysRoot "clang64\\share\\GNUstep\\Makefiles\\GNUstep.sh"
if (-not (Test-Path $envExe)) {
  throw "MSYS2 env.exe not found at $envExe"
}
if (-not (Test-Path $gnuStepSh)) {
  throw "GNUstep.sh not found at $gnuStepSh"
}

# Start bash in the working directory instead of cd-ing to a hand-built MSYS2
# path: the gnustep-cli managed root mounts drives under /cygdrive, a stock
# MSYS2 install at /c, and CHERE_INVOKING=1 keeps the login shell where it starts.
Set-Location -LiteralPath ([System.IO.Path]::GetFullPath($WorkingDirectory))
# bash -l has already sourced /etc/profile, which honours CHERE_INVOKING once
# and then unsets it; sourcing it again here would cd to $HOME.
$bootstrapLines = @(
  "export MSYSTEM=CLANG64",
  "export CHERE_INVOKING=1",
  "export PATH=/clang64/bin:/usr/bin:`$PATH",
  "export CC=clang",
  "export CXX=clang++",
  "export GNUSTEP_CONFIG_FILE=/clang64/etc/GNUstep/GNUstep.conf",
  "export GNUSTEP_MAKEFILES=/clang64/share/GNUstep/Makefiles",
  "export GNUSTEP_SYSTEM_ROOT=/clang64",
  "source /clang64/share/GNUstep/Makefiles/GNUstep.sh"
)

if ([string]::IsNullOrWhiteSpace($InnerCommand)) {
  $bootstrapLines += "exec bash -l"
} else {
  $bootstrapLines += $InnerCommand
}

$bootstrap = [string]::Join("; ", $bootstrapLines)
& $envExe 'MSYSTEM=CLANG64' 'CHERE_INVOKING=1' '/usr/bin/bash' '-lc' $bootstrap
exit $LASTEXITCODE
