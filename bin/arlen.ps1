[CmdletBinding(PositionalBinding = $false)]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CommandArguments = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "_windows_clang64_launcher.ps1")
$exitCode = Invoke-ArlenClang64Command -LauncherPath (Join-Path $PSScriptRoot "arlen") -CommandArguments $CommandArguments
exit $exitCode
