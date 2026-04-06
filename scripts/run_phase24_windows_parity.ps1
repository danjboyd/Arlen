param(
  [string]$MsysRoot = "C:\\msys64"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$launcher = Join-Path $PSScriptRoot "run_clang64.ps1"
& $launcher -MsysRoot $MsysRoot -InnerCommand "bash ./tools/ci/run_phase24_windows_parity.sh"
exit $LASTEXITCODE
