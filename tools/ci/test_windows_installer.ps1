<# Focused installer regressions. Fixtures and mocked network/bootstrap calls;
   no toolchain download or application compilation. Windows PowerShell 5.1. #>
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$installer = Join-Path $PSScriptRoot '..\install.ps1'
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('arlen installer tests ' + [Guid]::NewGuid().ToString('N'))
$savedPath = $env:Path
$savedUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$toolchainSha = '07d57993b2d5364578aff0392fede18d5a427f9f5dd22a03df1ec56c28f98dba'
$global:ArlenInstallerTestsetupCalls = 0
$global:ArlenInstallerTestdownloadMode = 'good'
$global:ArlenInstallerTestsetupExit = 0
$global:ArlenInstallerTesttests = 0
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Case([string]$Name, [scriptblock]$Body) { & $Body; $global:ArlenInstallerTesttests++; Write-Host "PASS $Name" }
function Fails([scriptblock]$Body, [string]$Pattern) {
  $caught = $false
  try { & $Body } catch { $caught = $true; Assert ("$_" -match $Pattern) "unexpected failure: $_" }
  Assert $caught "expected failure matching $Pattern"
}
function Write-Toolchain([string]$Root) {
  foreach ($relative in @('usr\bin', 'clang64\lib', 'clang64\share\GNUstep\Makefiles', 'state')) {
    New-Item -ItemType Directory -Force (Join-Path $Root $relative) | Out-Null
  }
  foreach ($relative in @('usr\bin\env.exe', 'clang64\lib\libcurl.dll.a', 'clang64\share\GNUstep\Makefiles\GNUstep.sh')) {
    [IO.File]::WriteAllText((Join-Path $Root $relative), '')
  }
  [IO.File]::WriteAllText((Join-Path $Root 'state\cli-state.json'), (@{toolchain_version='0.1.1'; toolchain_artifact_sha256=$toolchainSha} | ConvertTo-Json))
}
# PowerShell command resolution lets us intercept just the external boundary.
function powershell.exe {
  $global:ArlenInstallerTestsetupCalls++
  Assert (($args -join ' ') -match 'v0.1.1/release-manifest.json') 'setup manifest must be pinned'
  $rootIndex = [Array]::IndexOf($args, '--root')
  Assert ($rootIndex -ge 0) 'setup needs the selected root'
  if ($global:ArlenInstallerTestsetupExit -eq 0) {
    Write-Toolchain $args[$rootIndex + 1]
    # Match the upstream bootstrap's persistent PATH side effect.
    [Environment]::SetEnvironmentVariable('Path', ((Join-Path $args[$rootIndex + 1] 'bin') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')), 'User')
  }
  $global:LASTEXITCODE = $global:ArlenInstallerTestsetupExit
}
function Invoke-WebRequest {
  param([switch]$UseBasicParsing, [string]$Uri, [string]$OutFile)
  if ($global:ArlenInstallerTestdownloadMode -eq 'fail') { throw 'simulated interrupted download' }
  if ($Uri -like '*/gnustep-bootstrap.ps1') { [IO.File]::WriteAllText($OutFile, 'bootstrap fixture'); return }
  if ($Uri -like '*/SHA256SUMS') {
    $hash = (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $global:ArlenInstallerTestArchive -Algorithm SHA256).Hash
    if ($global:ArlenInstallerTestdownloadMode -eq 'bad-checksum') { $hash = '0' * 64 }
    [IO.File]::WriteAllText($OutFile, "$hash  arlen-0.3.0-windows-x64.zip"); return
  }
  Copy-Item -LiteralPath $global:ArlenInstallerTestArchive -Destination $OutFile
}
function Invoke-RestMethod {
  param([switch]$UseBasicParsing, [string]$Uri)
  Assert ($Uri -eq 'https://api.github.com/repos/danjboyd/Arlen/releases/latest') 'unexpected latest lookup'
  return [pscustomobject]@{ tag_name='v0.3.0' }
}
function Get-FileHash {
  param([string]$Algorithm, [string]$LiteralPath)
  if ($LiteralPath -like '*gnustep-bootstrap.ps1') {
    $hash = 'a41adbf84d38a6ae90f4bdbbe0b9c3e35136cb3ee695bf26b783c04972045034'
    if ($global:ArlenInstallerTestdownloadMode -eq 'bad-bootstrap') { $hash = '0' * 64 }
    return [pscustomobject]@{ Hash=$hash }
  }
  Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm $Algorithm
}
try {
  $tree = Join-Path $sandbox 'fixture\arlen-0.3.0'
  New-Item -ItemType Directory -Force $tree | Out-Null
  foreach ($relative in @('bin\arlen', 'build\arlen.exe', 'build\boomhauer.exe', 'build\eocc.exe', 'build\lib\libArlenFramework.a', 'build\.release-prebuilt')) {
    $file = Join-Path $tree $relative
    New-Item -ItemType Directory -Force (Split-Path -Parent $file) | Out-Null
    [IO.File]::WriteAllText($file, 'fixture')
  }
  [IO.File]::WriteAllText((Join-Path $tree '.arlen-dist'), "version=0.3.0`nkind=windows-x64`ntoolchain=0.1.1`ntoolchain_sha256=$toolchainSha`n")
  [IO.File]::WriteAllText((Join-Path $tree 'sentinel'), 'working install')
  $archive = Join-Path $sandbox 'fixture.zip'
  $global:ArlenInstallerTestArchive = $archive
  [IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $sandbox 'fixture'), $archive)
  $root = Join-Path $sandbox 'toolchain root'
  $prefix = Join-Path $sandbox 'Arlen install'
  $bin = Join-Path $prefix 'bin'
  Case 'NoSetup fails on an explicit missing root without provisioning' {
    Fails { & $installer -Archive $archive -Prefix $prefix -MsysRoot $root -NoSetup -NoPathUpdate } '-NoSetup'
    Assert ($global:ArlenInstallerTestsetupCalls -eq 0) 'NoSetup must never bootstrap'
    Assert (-not (Test-Path $prefix)) 'failed prerequisites must not activate a release'
  }
  Case 'bootstrap digest failure prevents execution' {
    $global:ArlenInstallerTestdownloadMode = 'bad-bootstrap'
    Fails { & $installer -Archive $archive -Prefix $prefix -MsysRoot $root -NoPathUpdate } 'bootstrap checksum mismatch'
    Assert ($global:ArlenInstallerTestsetupCalls -eq 0) 'unverified bootstrap ran'
  }
  Case 'failed prerequisite setup is actionable and retryable' {
    $global:ArlenInstallerTestdownloadMode = 'good'; $global:ArlenInstallerTestsetupExit = 17
    Fails { & $installer -Archive $archive -Prefix $prefix -MsysRoot $root -NoPathUpdate } 'setup failed.*17'
    Assert (-not (Test-Path $prefix)) 'failed setup changed install'
  }
  Case 'missing toolchain provisions pinned setup and registers PATH' {
    $global:ArlenInstallerTestsetupExit = 0
    & $installer -Archive $archive -Prefix $prefix -MsysRoot $root
    Assert ((Get-Command arlen).Source -eq (Join-Path $bin 'arlen.cmd')) 'bare arlen must resolve now'
    $userEntries = [Environment]::GetEnvironmentVariable('Path', 'User') -split ';'
    Assert ($userEntries[0] -eq $bin) 'new terminals must find launcher through saved user PATH'
  }
  $oldTarget = [string](Get-Item -LiteralPath (Join-Path $prefix 'current')).Target[0]
  Case 'download failure preserves current install and PATH' {
    $global:ArlenInstallerTestdownloadMode = 'fail'
    Fails { & $installer -Version 0.3.0 -Prefix $prefix -MsysRoot $root -NoSetup } 'download failed'
    Assert ((Get-Content (Join-Path $prefix 'current\sentinel')) -eq 'working install') 'download failure broke install'
  }
  Case 'archive checksum failure preserves current install' {
    $global:ArlenInstallerTestdownloadMode = 'bad-checksum'
    Fails { & $installer -Version 0.3.0 -Prefix $prefix -MsysRoot $root -NoSetup } 'checksum mismatch'
    Assert ([string](Get-Item -LiteralPath (Join-Path $prefix 'current')).Target[0] -eq $oldTarget) 'checksum failure switched install'
  }
  Case 'same-version retry retains old tree and PATH is idempotent' {
    $global:ArlenInstallerTestdownloadMode = 'good'
    & $installer -Version 0.3.0 -Prefix $prefix -MsysRoot $root -NoSetup
    Assert (Test-Path -LiteralPath (Join-Path $oldTarget 'sentinel')) 'retry removed old tree'
    Assert ([string](Get-Item -LiteralPath (Join-Path $prefix 'current')).Target[0] -ne $oldTarget) 'retry did not activate staged install'
    Assert (@($env:Path -split ';' | Where-Object { $_ -eq $bin }).Count -eq 1) 'process PATH duplicates'
    Assert (@([Environment]::GetEnvironmentVariable('Path', 'User') -split ';' | Where-Object { $_ -eq $bin }).Count -eq 1) 'user PATH duplicates'
  }
  Case 'NoPathUpdate preserves persistent user PATH' {
    $before = [Environment]::GetEnvironmentVariable('Path', 'User')
    & $installer -Archive $archive -Prefix (Join-Path $sandbox 'ephemeral') -MsysRoot $root -NoSetup -NoPathUpdate
    Assert ([Environment]::GetEnvironmentVariable('Path', 'User') -eq $before) 'NoPathUpdate changed saved PATH'
  }
  Case 'NoSetup rejects artifact drift and preserves active install' {
    $stateFile = Join-Path $root 'state\cli-state.json'
    $stateText = [IO.File]::ReadAllText($stateFile)
    [IO.File]::WriteAllText($stateFile, $stateText.Replace($toolchainSha, ('0' * 64)))
    try {
      Fails { & $installer -Archive $archive -Prefix $prefix -MsysRoot $root -NoSetup -NoPathUpdate } '-NoSetup'
      Assert ((Get-Content (Join-Path $prefix 'current\sentinel')) -eq 'working install') 'toolchain drift damaged current install'
    } finally { [IO.File]::WriteAllText($stateFile, $stateText) }
  }
  Case 'ordinary current directory is never deleted' {
    $otherPrefix = Join-Path $sandbox 'ordinary current'
    $ordinaryCurrent = Join-Path $otherPrefix 'current'
    New-Item -ItemType Directory -Force $ordinaryCurrent | Out-Null
    [IO.File]::WriteAllText((Join-Path $ordinaryCurrent 'sentinel'), 'preserve')
    Fails { & $installer -Archive $archive -Prefix $otherPrefix -MsysRoot $root -NoSetup -NoPathUpdate } 'not a junction'
    Assert ((Get-Content (Join-Path $ordinaryCurrent 'sentinel')) -eq 'preserve') 'ordinary current was removed'
  }
  Case 'incomplete prebuilt archive never activates or runs setup' {
    $incompleteTree = Join-Path $sandbox 'incomplete\arlen-0.3.0'
    New-Item -ItemType Directory -Force $incompleteTree | Out-Null
    Copy-Item -LiteralPath (Join-Path $tree '.arlen-dist') -Destination $incompleteTree
    $incompleteArchive = Join-Path $sandbox 'incomplete.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory((Split-Path -Parent $incompleteTree), $incompleteArchive)
    $beforeCalls = $global:ArlenInstallerTestsetupCalls
    Fails { & $installer -Archive $incompleteArchive -Prefix $prefix -MsysRoot $root -NoPathUpdate } 'archive lacks prebuilt'
    Assert ($global:ArlenInstallerTestsetupCalls -eq $beforeCalls) 'incomplete archive ran setup'
    Assert ((Get-Content (Join-Path $prefix 'current\sentinel')) -eq 'working install') 'incomplete archive damaged install'
  }
  Case 'default irm/iex-style execution registers bare arlen immediately' {
    $savedLocal = $env:LOCALAPPDATA
    $savedMsys = $env:ARLEN_MSYS_ROOT
    $savedMakefiles = $env:GNUSTEP_MAKEFILES
    try {
      $env:LOCALAPPDATA = Join-Path $sandbox 'default user'
      $env:ARLEN_MSYS_ROOT = $null
      $env:GNUSTEP_MAKEFILES = $null
      Write-Toolchain (Join-Path $env:LOCALAPPDATA 'gnustep-cli')
      Invoke-Expression ([IO.File]::ReadAllText((Resolve-Path $installer)))
      Assert ((Get-Command arlen).Source -eq (Join-Path $env:LOCALAPPDATA 'Arlen\bin\arlen.cmd')) 'iex did not update current-shell command resolution'
    } finally {
      $env:LOCALAPPDATA = $savedLocal
      $env:ARLEN_MSYS_ROOT = $savedMsys
      $env:GNUSTEP_MAKEFILES = $savedMakefiles
    }
  }
  Case 'NoPathUpdate also suppresses upstream bootstrap PATH registration' {
    $before = [Environment]::GetEnvironmentVariable('Path', 'User')
    & $installer -Archive $archive -Prefix (Join-Path $sandbox 'setup no path') -MsysRoot (Join-Path $sandbox 'new toolchain') -NoPathUpdate
    Assert ([Environment]::GetEnvironmentVariable('Path', 'User') -eq $before) 'upstream setup changed PATH despite NoPathUpdate'
  }
  # Load the same implementation so filesystem boundaries can be faulted
  # without CLI-only test switches or a second activation implementation.
  $faultPrefix = Join-Path $sandbox 'transaction install'
  . $installer -Archive $archive -Prefix $faultPrefix -MsysRoot $root -NoSetup -NoPathUpdate
  $faultPs1 = Join-Path $faultPrefix 'bin\arlen-clang64.ps1'
  $faultCmd = Join-Path $faultPrefix 'bin\arlen.cmd'
  $oldPs1 = "[Console]::WriteLine('previous-working-launcher'); exit 0"
  $oldCmd = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0arlen-clang64.ps1`"`r`nexit /b %ERRORLEVEL%`r`n"
  [IO.File]::WriteAllText($faultPs1, $oldPs1)
  [IO.File]::WriteAllText($faultCmd, $oldCmd)
  $faultTarget = [string](Get-Item -LiteralPath (Join-Path $faultPrefix 'current')).Target[0]
  $global:ArlenInstallerTestFault = ''
  function Write-ArlenLauncherStage($Path, $Body, $Encoding) {
    if ($global:ArlenInstallerTestFault -eq 'second stage write' -and $Path -like '*arlen.cmd.*.new') { throw 'injected second stage write' }
    [IO.File]::WriteAllText($Path, $Body, $Encoding)
  }
  function Move-ArlenActivationFile($Source, $Destination) {
    if ($global:ArlenInstallerTestFault -eq 'second launcher publish' -and $Destination -like '*\arlen.cmd') { throw 'injected second launcher publish' }
    [IO.File]::Move($Source, $Destination)
  }
  function Move-ArlenActivationJunction($Source, $Destination) {
    if ($global:ArlenInstallerTestFault -eq 'junction switch') { throw 'injected junction switch' }
    [IO.Directory]::Move($Source, $Destination)
  }
  function New-Item {
    param([string]$Path, [string]$ItemType, [string]$Target, [switch]$Force)
    if ($global:ArlenInstallerTestFault -eq 'junction creation' -and $ItemType -eq 'Junction' -and $Path -like '*\.current-install-*') { throw 'injected junction creation' }
    Microsoft.PowerShell.Management\New-Item @PSBoundParameters
  }
  function Assert-PreviousLauncher {
    Assert ([IO.File]::ReadAllText($faultPs1) -eq $oldPs1) 'previous ps1 content changed'
    Assert ([IO.File]::ReadAllText($faultCmd) -eq $oldCmd) 'previous cmd content changed'
    Assert ([string](Get-Item -LiteralPath (Join-Path $faultPrefix 'current')).Target[0] -eq $faultTarget) 'previous junction changed'
    $output = & arlen
    Assert ($LASTEXITCODE -eq 0 -and $output -eq 'previous-working-launcher') 'previous bare arlen stopped working'
  }
  foreach ($faultMode in @('second stage write', 'second launcher publish', 'junction creation', 'junction switch')) {
    $global:ArlenInstallerTestFault = $faultMode
    Case "activation rollback after $faultMode" {
      Fails { Install-Arlen -Archive $archive -Prefix $faultPrefix -BinDir (Join-Path $faultPrefix 'bin') -MsysRoot $root -NoSetup -NoPathUpdate } 'injected'
      Assert-PreviousLauncher
    }
  }
  $global:ArlenInstallerTestFault = ''
  Case 'concurrent prefix installer rejected before activation' {
    $held = [IO.File]::Open(($faultPrefix + '.install.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    try {
      Fails { Install-Arlen -Archive $archive -Prefix $faultPrefix -MsysRoot $root -NoSetup -NoPathUpdate } 'another installer'
      Assert-PreviousLauncher
    } finally { $held.Dispose() }
  }
  Case 'different prefixes sharing a launcher directory cannot activate concurrently' {
    $held = [IO.File]::Open((Join-Path $faultPrefix 'bin.install.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    try {
      Fails { Install-Arlen -Archive $archive -Prefix (Join-Path $sandbox 'other prefix') -BinDir (Join-Path $faultPrefix 'bin') -MsysRoot $root -NoSetup -NoPathUpdate } 'another installer'
      Assert-PreviousLauncher
    } finally { $held.Dispose() }
  }
  Write-Host "Windows installer regressions passed: $global:ArlenInstallerTesttests"
} finally {
  $env:Path = $savedPath
  [Environment]::SetEnvironmentVariable('Path', $savedUserPath, 'User')
  # Remove checked junctions without recursing through their targets on PS5.1.
  if ([IO.Path]::GetFullPath($sandbox).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) {
    Get-ChildItem -LiteralPath $sandbox -Filter current -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.LinkType -eq 'Junction' } | ForEach-Object { [IO.Directory]::Delete($_.FullName) }
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
  }
}
