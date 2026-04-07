[CmdletBinding(PositionalBinding = $false)]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CommandArguments = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "_windows_clang64_launcher.ps1")

if ($CommandArguments.Count -ge 1 -and $CommandArguments[0] -eq "service") {
  if ($CommandArguments.Count -lt 2) {
    Write-Error "arlen service: missing subcommand"
    exit 2
  }

  $subcommand = [string]$CommandArguments[1]
  $remaining = if ($CommandArguments.Count -gt 2) { $CommandArguments[2..($CommandArguments.Count - 1)] } else { @() }
  $frameworkRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

  switch ($subcommand) {
    "install" {
      $scriptPath = Join-Path $frameworkRoot "tools\deploy\windows\install_service.ps1"
      & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath @remaining
      exit $LASTEXITCODE
    }
    "uninstall" {
      $scriptPath = Join-Path $frameworkRoot "tools\deploy\windows\uninstall_service.ps1"
      & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath @remaining
      exit $LASTEXITCODE
    }
    "start" {
      $scriptPath = Join-Path $frameworkRoot "tools\deploy\windows\service_control.ps1"
      & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Action start @remaining
      exit $LASTEXITCODE
    }
    "stop" {
      $scriptPath = Join-Path $frameworkRoot "tools\deploy\windows\service_control.ps1"
      & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Action stop @remaining
      exit $LASTEXITCODE
    }
    "status" {
      $scriptPath = Join-Path $frameworkRoot "tools\deploy\windows\service_control.ps1"
      & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Action status @remaining
      exit $LASTEXITCODE
    }
    "enable" {
      $scriptPath = Join-Path $frameworkRoot "tools\deploy\windows\service_control.ps1"
      & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Action enable @remaining
      exit $LASTEXITCODE
    }
  }
}

$exitCode = Invoke-ArlenClang64Command -LauncherPath (Join-Path $PSScriptRoot "arlen") -CommandArguments $CommandArguments
exit $exitCode
