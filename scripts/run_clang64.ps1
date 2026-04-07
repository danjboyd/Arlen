param(
  [string]$InnerCommand = "",
  [string]$WorkingDirectory = (Join-Path $PSScriptRoot ".."),
  [string]$MsysRoot = "C:\\msys64"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-ToMsysPath {
  param([Parameter(Mandatory = $true)][string]$WindowsPath)

  $fullPath = [System.IO.Path]::GetFullPath($WindowsPath)
  $normalized = $fullPath -replace "\\", "/"
  if ($normalized -match "^([A-Za-z]):(/.*)?$") {
    $drive = $Matches[1].ToLowerInvariant()
    $rest = if ($Matches[2]) { $Matches[2] } else { "" }
    return "/$drive$rest"
  }

  throw "Unable to convert Windows path to MSYS2 path: $WindowsPath"
}

$envExe = Join-Path $MsysRoot "usr\\bin\\env.exe"
$gnuStepSh = Join-Path $MsysRoot "clang64\\share\\GNUstep\\Makefiles\\GNUstep.sh"
if (-not (Test-Path $envExe)) {
  throw "MSYS2 env.exe not found at $envExe"
}
if (-not (Test-Path $gnuStepSh)) {
  throw "GNUstep.sh not found at $gnuStepSh"
}

$workingDirectoryMsys = Convert-ToMsysPath -WindowsPath $WorkingDirectory
$bootstrapLines = @(
  "source /etc/profile",
  "export MSYSTEM=CLANG64",
  "export CHERE_INVOKING=1",
  "export PATH=/clang64/bin:/usr/bin:`$PATH",
  "export CC=clang",
  "export CXX=clang++",
  "export GNUSTEP_CONFIG_FILE=/clang64/etc/GNUstep/GNUstep.conf",
  "export GNUSTEP_MAKEFILES=/clang64/share/GNUstep/Makefiles",
  "export GNUSTEP_SYSTEM_ROOT=/clang64",
  "source /clang64/share/GNUstep/Makefiles/GNUstep.sh",
  "cd '$workingDirectoryMsys'"
)

if ([string]::IsNullOrWhiteSpace($InnerCommand)) {
  $bootstrapLines += "exec bash -l"
} else {
  $bootstrapLines += $InnerCommand
}

$bootstrap = [string]::Join("; ", $bootstrapLines)
& $envExe 'MSYSTEM=CLANG64' 'CHERE_INVOKING=1' '/usr/bin/bash' '-lc' $bootstrap
exit $LASTEXITCODE
