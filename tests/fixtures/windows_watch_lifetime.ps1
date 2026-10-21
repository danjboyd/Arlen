param(
  [Parameter(Mandatory=$true)][string]$FrameworkRoot,
  [Parameter(Mandatory=$true)][string]$AppRoot,
  [Parameter(Mandatory=$true)][string]$BashPath,
  [Parameter(Mandatory=$true)][int]$Port
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$watch = $null
$env:ARLEN_FRAMEWORK_ROOT = $FrameworkRoot
$env:ARLEN_APP_ROOT = $AppRoot
$env:ARLEN_BOOMHAUER_BUILD_ERROR_RETRY_SECONDS = '0'
function Listening {
  return @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue).Count -gt 0
}
function Wait-Listening([bool]$Expected, [int]$Seconds) {
  $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
  do {
    if ((Listening) -eq $Expected) { return }
    Start-Sleep -Milliseconds 100
  } while ([DateTime]::UtcNow -lt $deadline)
  throw "watch listen state did not become $Expected on port $Port"
}
function Kill-WatchTree {
  $savedPreference = $ErrorActionPreference
  try {
    # Job closure can kill a descendant before taskkill reaches it. Its exit
    # code then reports a race; assert process/port lifetime below instead.
    $ErrorActionPreference = 'Continue'
    & taskkill.exe /F /T /PID $watch.Id 2>&1 | Out-Null
  } finally { $ErrorActionPreference = $savedPreference }
}
try {
  if (Listening) { throw "fixture port $Port is already occupied" }
  foreach ($mode in @('app', 'build-error')) {
    $source = Join-Path $AppRoot 'app_lite.m'
    if ($mode -eq 'build-error') { Add-Content -LiteralPath $source -Value "`n#error WATCH_LIFETIME_FAILURE" }
    $log = Join-Path $AppRoot "lifetime-$mode.log"
    $entry = ($FrameworkRoot -replace '\\','/') + '/bin/boomhauer'
    $entry = $entry.Replace("'", "'`"'`"'")
    $command = "exec bash '$entry' --watch --port $Port"
    $watch = Start-Process -FilePath $BashPath -ArgumentList @('-lc', ('"' + $command + '"')) `
      -WorkingDirectory $AppRoot -WindowStyle Hidden -PassThru `
      -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    Wait-Listening $true 90
    $owners = @(Get-NetTCPConnection -LocalPort $Port -State Listen).OwningProcess | Select-Object -Unique
    # The old setsid path kept the server alive even after this whole tree died.
    Kill-WatchTree
    if (-not $watch.WaitForExit(10000)) { throw 'watch parent survived force-kill' }
    Wait-Listening $false 10
    foreach ($owner in $owners) {
      if (Get-Process -Id $owner -ErrorAction SilentlyContinue) { throw "$mode server $owner survived watch termination" }
    }
    Write-Output "watch-lifetime-passed: $mode"
    $watch = $null
  }
} catch {
  Get-ChildItem -LiteralPath $AppRoot -Filter 'lifetime-*.log*' | ForEach-Object {
    Write-Output $_.Name
    Get-Content -LiteralPath $_.FullName -Tail 20
  }
  throw
} finally {
  if ($watch -and -not $watch.HasExited) { Kill-WatchTree }
}
