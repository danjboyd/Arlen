param(
  [Parameter(Mandatory = $true)][string]$SourceRoot,
  [Parameter(Mandatory = $true)][string]$ExpectedSource,
  [Parameter(Mandatory = $true)][string]$OutputDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$OutputDir = [IO.Path]::GetFullPath($OutputDir)
if (Test-Path -LiteralPath $OutputDir) { throw 'Public evidence directory must be new' }
New-Item -ItemType Directory -Path $OutputDir | Out-Null
$summary = [ordered]@{ status='running'; expectedVersion='0.3.2'; expectedSource=$ExpectedSource; selection='Actual public latest installer; no installer Archive or Version override' }
try {
  $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/danjboyd/Arlen/releases/latest'
  if ($release.tag_name -ne 'v0.3.2' -or $release.draft -or $release.prerelease) { throw 'Wrong public latest release' }
  $wanted = @('arlen-0.3.2.tar.gz','arlen-0.3.2-macos-arm64.tar.gz','arlen-0.3.2-windows-x64.zip','install.sh','install.ps1','SHA256SUMS')
  if (@(Compare-Object ($wanted | Sort-Object) (@($release.assets.name) | Sort-Object)).Count -ne 0) { throw 'Public release assets are incomplete' }
  [IO.File]::WriteAllText((Join-Path $OutputDir 'public-latest.json'), ($release | ConvertTo-Json -Depth 12))
  $downloads = Join-Path $OutputDir 'downloads'
  New-Item -ItemType Directory -Path $downloads | Out-Null
  foreach ($name in @('install.ps1','SHA256SUMS','arlen-0.3.2-windows-x64.zip')) {
    Invoke-WebRequest -UseBasicParsing -Uri ('https://github.com/danjboyd/Arlen/releases/latest/download/' + $name) -OutFile (Join-Path $downloads $name)
  }
  $hashes = @{}
  foreach ($line in Get-Content -LiteralPath (Join-Path $downloads 'SHA256SUMS')) {
    if ($line -match '^([0-9a-f]{64})\s+\*?(.+)$') { $hashes[$Matches[2]] = $Matches[1] }
  }
  foreach ($name in @('install.ps1','arlen-0.3.2-windows-x64.zip')) {
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $downloads $name)).Hash.ToLowerInvariant()
    if ($actual -ne $hashes[$name]) { throw "Public checksum mismatch: $name" }
  }
  # Reuse the tagged release's maintained installer/first-app contract. Only
  # installer selection, source/helper paths and evidence destination change.
  # Its Archive parameter records the checked public ZIP; it is not forwarded
  # to the public installer, which must select and download latest itself.
  $contract = [IO.File]::ReadAllText((Join-Path $SourceRoot 'tools\ci\run_windows_release_certification.ps1'))
  function Replace-One([string]$Old, [string]$New) {
    if ([regex]::Matches($script:contract, [regex]::Escape($Old)).Count -ne 1) { throw "Maintained contract changed: $Old" }
    $script:contract = $script:contract.Replace($Old, $New)
  }
  function Quote-PS([string]$Value) { return "'" + $Value.Replace("'", "''") + "'" }
  Replace-One ". (Join-Path `$PSScriptRoot 'windows_installer_test_lock.ps1')" ('. ' + (Quote-PS (Join-Path $SourceRoot 'tools\ci\windows_installer_test_lock.ps1')))
  Replace-One '$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path' ('$repoRoot = ' + (Quote-PS $SourceRoot))
  Replace-One '$summaryDir = Join-Path $repoRoot "build\release_confidence\windows"' ('$summaryDir = ' + (Quote-PS (Join-Path $OutputDir 'maintained-contract')))
  Replace-One '& (Join-Path $repoRoot "tools\install.ps1") -Archive $Archive -Prefix $prefix -BinDir $binDir' ('& ' + (Quote-PS (Join-Path $downloads 'install.ps1')) + ' -Prefix $prefix -BinDir $binDir')
  $restore = "[Environment]::SetEnvironmentVariable('Path', `$savedUserPath, 'User')"
  $proof = @'
  if ([Environment]::GetEnvironmentVariable('Path', 'User') -cne $savedUserPath -or $env:Path -cne $savedProcessPath) { throw 'Installer PATH restoration failed' }
  [IO.File]::WriteAllText((Join-Path $summaryDir 'path-restored.json'), '{"user_path_restored":true,"process_path_restored":true,"guard":"maintained per-user installer mutex"}')
'@
  Replace-One $restore ($restore + "`r`n" + $proof)
  $derived = Join-Path $OutputDir 'public-maintained-contract.ps1'
  [IO.File]::WriteAllText($derived, $contract)
  $tokens = $null; $parseErrors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($derived,[ref]$tokens,[ref]$parseErrors)
  if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
  $work = Join-Path $OutputDir 'work'
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $derived -Archive (Join-Path $downloads 'arlen-0.3.2-windows-x64.zip') -WorkDir $work -KeepWorkDir
  if ($LASTEXITCODE -ne 0) { throw "Maintained public installer contract exited $LASTEXITCODE" }
  $dist = @{}
  foreach ($line in Get-Content -LiteralPath (Join-Path $work 'Arlen\current\.arlen-dist')) {
    $pair = $line -split '=',2
    if ($pair.Count -eq 2) { $dist[$pair[0]] = $pair[1] }
  }
  if ($dist['version'] -ne '0.3.2' -or $dist['commit'] -ne $ExpectedSource) { throw 'Installed version/source mismatch' }
  $contractSummary = Get-Content -Raw -LiteralPath (Join-Path $OutputDir 'maintained-contract\summary.json') | ConvertFrom-Json
  $restored = Get-Content -Raw -LiteralPath (Join-Path $OutputDir 'maintained-contract\path-restored.json') | ConvertFrom-Json
  if ($contractSummary.status -ne 'pass' -or -not $restored.user_path_restored -or -not $restored.process_path_restored) { throw 'Incomplete maintained public contract' }
  $summary.status = 'pass'; $summary['installedDist'] = $dist; $summary['checksums'] = $hashes; $summary['maintainedContract'] = $contractSummary; $summary['pathRestoration'] = $restored
} catch {
  $summary.status = 'fail'; $summary['error'] = "$_"
  throw
} finally {
  [IO.File]::WriteAllText((Join-Path $OutputDir 'summary.json'), ($summary | ConvertTo-Json -Depth 12))
}
