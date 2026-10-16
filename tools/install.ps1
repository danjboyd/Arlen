<#
Install an Arlen release on Windows and put an `arlen` command on your PATH.

  irm https://github.com/danjboyd/Arlen/releases/latest/download/install.ps1 | iex
  & ([scriptblock]::Create((irm https://github.com/danjboyd/Arlen/releases/latest/download/install.ps1))) -Version 0.3.0

Options:
  -Version X.Y.Z   release to install (default: the latest release)
  -Prefix DIR      where releases are unpacked (default: %LOCALAPPDATA%\Arlen)
  -BinDir DIR      where the `arlen` launcher goes (default: <Prefix>\bin)
  -Archive FILE    install from a downloaded release zip instead
  -MsysRoot DIR    the gnustep-cli managed MSYS2 CLANG64 root (default: auto-detect)

Windows gets the prebuilt arlen-X.Y.Z-windows-x64.zip. It runs on the
gnustep-cli managed MSYS2 CLANG64 toolchain, and that toolchain's version must
match the one the zip was built against. See docs/GETTING_STARTED_WINDOWS.md.

Must stay Windows PowerShell 5.1 compatible, and safe to run through
`irm | iex`: no `exit`, and every setting stays inside Install-Arlen.
#>
param(
  [string]$Version = "",
  [string]$Prefix = "",
  [string]$BinDir = "",
  [string]$Archive = "",
  [string]$MsysRoot = ""
)

function Install-Arlen {
  param(
    [string]$Version,
    [string]$Prefix,
    [string]$BinDir,
    [string]$Archive,
    [string]$MsysRoot
  )

  Set-StrictMode -Version Latest
  $ErrorActionPreference = "Stop"
  # Invoke-WebRequest's progress bar slows 5.1 downloads by an order of magnitude.
  $ProgressPreference = "SilentlyContinue"

  $repoSlug = "danjboyd/Arlen"
  $bootstrapSetup = "iwr https://raw.githubusercontent.com/danjboyd/gnustep-cli-new/v0.1.0/scripts/bootstrap/gnustep-bootstrap.ps1 -OutFile gnustep-bootstrap.ps1`n" +
    "  powershell -ExecutionPolicy Bypass -File .\gnustep-bootstrap.ps1 setup --user --manifest https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0/release-manifest.json"
  function Say([string]$Message) { Write-Host "arlen-install: $Message" }
  function Die([string]$Message) { throw "arlen-install: error: $Message" }

  if (-not $Prefix) { $Prefix = Join-Path $env:LOCALAPPDATA "Arlen" }
  if (-not $BinDir) { $BinDir = Join-Path $Prefix "bin" }
  $Version = $Version -replace '^v', ''

  if (-not [Environment]::Is64BitOperatingSystem) {
    Die "Arlen's Windows release is x64 only"
  }

  # scripts/run_clang64.ps1's search order, plus the root that gnustep-cli
  # setup records in GNUSTEP_MAKEFILES (it may have been given --root).
  $candidates = @()
  if ($MsysRoot) { $candidates += $MsysRoot }
  if ($env:ARLEN_MSYS_ROOT) { $candidates += $env:ARLEN_MSYS_ROOT }
  $makefilesSuffix = "\clang64\share\GNUstep\Makefiles"
  if ($env:GNUSTEP_MAKEFILES -and $env:GNUSTEP_MAKEFILES.TrimEnd('\').EndsWith($makefilesSuffix, [StringComparison]::OrdinalIgnoreCase)) {
    $trimmed = $env:GNUSTEP_MAKEFILES.TrimEnd('\')
    $candidates += $trimmed.Substring(0, $trimmed.Length - $makefilesSuffix.Length)
  }
  if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA "gnustep-cli") }
  if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles "gnustep-cli") }
  $resolvedRoot = $null
  foreach ($candidate in $candidates) {
    if ((Test-Path (Join-Path $candidate "usr\bin\env.exe")) -and
        (Test-Path (Join-Path $candidate "clang64\share\GNUstep\Makefiles\GNUstep.sh"))) {
      $resolvedRoot = $candidate
      break
    }
  }
  if (-not $resolvedRoot) {
    Die @"
no gnustep-cli managed MSYS2 CLANG64 toolchain was found (tried: $([string]::Join(', ', $candidates))).

Arlen's Windows release runs on the gnustep-cli managed toolchain. Install it
for your user with the gnustep-cli PowerShell bootstrap:

  $bootstrapSetup

Then rerun this installer. If the toolchain lives somewhere else, pass
-MsysRoot or set ARLEN_MSYS_ROOT. See docs/GETTING_STARTED_WINDOWS.md.
"@
  }
  # Arlen links -lcurl, which the managed toolchain doesn't ship yet.
  if (-not (Test-Path (Join-Path $resolvedRoot "clang64\lib\libcurl.dll.a"))) {
    Die @"
libcurl is missing from $resolvedRoot. Install it inside the toolchain, then rerun this installer:

  & '$(Join-Path $resolvedRoot "usr\bin\bash.exe")' -lc 'pacman -S --noconfirm --needed mingw-w64-clang-x86_64-curl'

Use plain pacman -S exactly as shown. Never run pacman -Sy or -Syu in the managed toolchain:
a partial upgrade breaks its python and clang.
"@
  }

  # PowerShell 5.1 defaults to TLS 1.0/1.1, which GitHub refuses.
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor
      [Net.SecurityProtocolType]::Tls12

  $workDir = Join-Path ([IO.Path]::GetTempPath()) ("arlen-install-" + [Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $workDir | Out-Null
  try {
    if (-not $Archive) {
      if (-not $Version) {
        try {
          $latest = Invoke-RestMethod -UseBasicParsing "https://api.github.com/repos/$repoSlug/releases/latest"
        } catch {
          Die "could not look up the latest release: $($_.Exception.Message)"
        }
        $Version = ([string]$latest.tag_name) -replace '^v', ''
        if ($Version -notmatch '^\d+\.\d+\.\d+$') {
          Die "could not determine the latest release version (got '$Version')"
        }
      }
      $asset = "arlen-$Version-windows-x64.zip"
      $baseUrl = "https://github.com/$repoSlug/releases/download/v$Version"
      Say "downloading Arlen $Version ($asset)"
      $Archive = Join-Path $workDir $asset
      $sumsPath = Join-Path $workDir "SHA256SUMS"
      try {
        Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/$asset" -OutFile $Archive
      } catch {
        Die "download failed: $baseUrl/$asset ($($_.Exception.Message))"
      }
      try {
        Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/SHA256SUMS" -OutFile $sumsPath
      } catch {
        Die "download failed: $baseUrl/SHA256SUMS ($($_.Exception.Message))"
      }
      $expected = $null
      foreach ($line in [IO.File]::ReadAllLines($sumsPath)) {
        $fields = $line -split '\s+', 2
        if ($fields.Count -eq 2 -and $fields[1].TrimStart('*') -eq $asset) { $expected = $fields[0].ToLowerInvariant() }
      }
      if (-not $expected) { Die "SHA256SUMS has no entry for $asset" }
      $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Archive).Hash.ToLowerInvariant()
      if ($expected -ne $actual) { Die "checksum mismatch for $asset (expected $expected, got $actual)" }
      Say "checksum verified"
    } elseif (-not (Test-Path -LiteralPath $Archive -PathType Leaf)) {
      Die "archive not found: $Archive"
    }

    Say "unpacking"
    $unpack = Join-Path $workDir "unpack"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    # Faster than Expand-Archive on 5.1, and keeps each entry's timestamp, so
    # `make` sees the prebuilt tools as up to date.
    [IO.Compression.ZipFile]::ExtractToDirectory((Resolve-Path -LiteralPath $Archive).Path, $unpack)
    $tops = @(Get-ChildItem -LiteralPath $unpack)
    if ($tops.Count -ne 1 -or -not (Test-Path (Join-Path $tops[0].FullName ".arlen-dist"))) {
      Die "$Archive is not an Arlen release archive"
    }
    $top = $tops[0].FullName
    $dist = @{}
    foreach ($line in [IO.File]::ReadAllLines((Join-Path $top ".arlen-dist"))) {
      $pair = $line -split '=', 2
      if ($pair.Count -eq 2) { $dist[$pair[0].Trim()] = $pair[1].Trim() }
    }
    if (-not $dist["version"]) { Die "$Archive has no version in .arlen-dist" }
    if ($dist["kind"] -ne "windows-x64") {
      Die "$Archive is a '$($dist["kind"])' archive; Windows needs arlen-X.Y.Z-windows-x64.zip"
    }
    $Version = $dist["version"]

    # The prebuilt DLLs follow the toolchain's ABI. A rebuilt toolchain can be
    # republished under the same version, so the artifact checksum also counts.
    $wantToolchain = $dist["toolchain"]
    $wantToolchainSha = $dist["toolchain_sha256"]
    $state = Get-GnustepToolchainState -Root $resolvedRoot
    if (-not $state) {
      Say "warning: $resolvedRoot has no gnustep-cli state (state\cli-state.json), so its toolchain version is unknown; Arlen $Version expects gnustep-cli toolchain $wantToolchain"
    } elseif ($wantToolchain -and $state.Version -ne $wantToolchain) {
      Die @"
Arlen $Version was built against gnustep-cli toolchain $wantToolchain, but $resolvedRoot has $($state.Version).
Rerun the gnustep-cli bootstrap setup to install toolchain $($wantToolchain):

  $bootstrapSetup

Then rerun this installer.
"@
    } elseif ($wantToolchainSha -and $state.Sha256 -and $state.Sha256 -ne $wantToolchainSha.ToLowerInvariant()) {
      Say "warning: $resolvedRoot has a different build of gnustep-cli toolchain $wantToolchain than Arlen $Version was built against; if arlen fails to start, rerun the gnustep-cli bootstrap setup"
    }

    New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
    $dest = Join-Path $Prefix $Version
    if (Test-Path -LiteralPath $dest) {
      Say "replacing existing $dest"
      Remove-Item -LiteralPath $dest -Recurse -Force
    }
    Move-Item -LiteralPath $top -Destination $dest
  } finally {
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
  }

  # A junction needs no admin rights or Developer Mode, unlike a symlink.
  # rmdir removes only the link; Remove-Item on 5.1 can follow it into the target.
  $current = Join-Path $Prefix "current"
  if (Test-Path -LiteralPath $current) { cmd /c rmdir "$current" | Out-Null }
  New-Item -ItemType Junction -Path $current -Target $dest | Out-Null

  New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
  # The .cmd works from cmd.exe and PowerShell alike, whatever the execution
  # policy. The .ps1 has a different name so PowerShell never picks it over the .cmd.
  $launcherPs1 = Join-Path $BinDir "arlen-clang64.ps1"
  $launcherCmd = Join-Path $BinDir "arlen.cmd"
  $launcherBody = @'
# Installed by Arlen's tools/install.ps1. Set ARLEN_HOME to use another install,
# and ARLEN_MSYS_ROOT to use another MSYS2 CLANG64 root.
$ErrorActionPreference = "Stop"
$arlenHome = if ($env:ARLEN_HOME) { $env:ARLEN_HOME } else { '__CURRENT__' }
$candidates = @()
if ($env:ARLEN_MSYS_ROOT) { $candidates += $env:ARLEN_MSYS_ROOT }
$candidates += '__MSYS_ROOT__'
if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA "gnustep-cli") }
if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles "gnustep-cli") }
$envExe = $null
foreach ($candidate in $candidates) {
  $probe = Join-Path $candidate "usr\bin\env.exe"
  if ((Test-Path $probe) -and (Test-Path (Join-Path $candidate "clang64\share\GNUstep\Makefiles\GNUstep.sh"))) {
    $envExe = $probe
    break
  }
}
if (-not $envExe) {
  [Console]::Error.WriteLine("arlen: no gnustep-cli MSYS2 CLANG64 root found (tried: $([string]::Join(', ', $candidates)))")
  exit 1
}
# Apps live outside the install, so arlen cannot find the framework by walking
# up from the app directory. cygpath handles both /c and /cygdrive/c mounts.
# build\dll holds the DLLs Arlen ships that the toolchain lacks (libpq.dll).
# Arlen loads them by absolute path under ARLEN_FRAMEWORK_ROOT; putting the
# directory first on PATH also covers tools that look them up by name.
$bootstrap = 'export PATH=/clang64/bin:/usr/bin:$PATH CC=clang CXX=clang++ ' +
  'GNUSTEP_CONFIG_FILE=/clang64/etc/GNUstep/GNUstep.conf ' +
  'GNUSTEP_MAKEFILES=/clang64/share/GNUstep/Makefiles GNUSTEP_SYSTEM_ROOT=/clang64; ' +
  'source /clang64/share/GNUstep/Makefiles/GNUstep.sh >/dev/null || exit 1; ' +
  'arlen_home="$(cygpath -u "$ARLEN_HOME_WIN")"; ' +
  'export PATH="$arlen_home/build/dll:$PATH"; ' +
  'export ARLEN_FRAMEWORK_ROOT="${ARLEN_FRAMEWORK_ROOT:-$arlen_home}"; ' +
  'exec "$arlen_home/bin/arlen" "$@"'
# bash -l sources /etc/profile, which keeps the current directory only while
# CHERE_INVOKING is set. Arguments follow "arlen" as $1, $2, ...
& $envExe 'MSYSTEM=CLANG64' 'CHERE_INVOKING=1' "ARLEN_HOME_WIN=$arlenHome" '/usr/bin/bash' '-lc' $bootstrap 'arlen' @args
exit $LASTEXITCODE
'@
  $launcherBody = $launcherBody.Replace('__CURRENT__', $current.Replace("'", "''")).Replace('__MSYS_ROOT__', $resolvedRoot.Replace("'", "''"))
  [IO.File]::WriteAllText($launcherPs1, $launcherBody, (New-Object Text.UTF8Encoding $false))
  $cmdBody = "@echo off`r`n" +
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0arlen-clang64.ps1`" %*`r`n" +
    "exit /b %ERRORLEVEL%`r`n"
  [IO.File]::WriteAllText($launcherCmd, $cmdBody, (New-Object Text.ASCIIEncoding))

  Say "installed Arlen $Version at $dest"
  Say "toolchain: $resolvedRoot"
  Say "launcher: $launcherCmd"
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $onPath = @(($userPath, $env:Path) -join ';' -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ieq $BinDir.TrimEnd('\')) }).Count -gt 0
  if (-not $onPath) {
    Say "add $BinDir to your PATH, for example (then open a new terminal):"
    Write-Host "  [Environment]::SetEnvironmentVariable('Path', `"$BinDir;`" + [Environment]::GetEnvironmentVariable('Path', 'User'), 'User')"
  }
  Write-Host ""
  Write-Host "Next:"
  Write-Host "  arlen doctor"
  Write-Host "  arlen new MyApp; cd MyApp; arlen boomhauer --port 3000"
}

function Get-GnustepToolchainState {
  param([string]$Root)
  # gnustep-cli setup writes this; without it the toolchain wasn't installed by gnustep-cli.
  $path = Join-Path $Root "state\cli-state.json"
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  try {
    $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  } catch {
    return $null
  }
  $names = $state.PSObject.Properties.Name
  if (-not ($names -contains "toolchain_version") -or -not $state.toolchain_version) { return $null }
  $sha = if ($names -contains "toolchain_artifact_sha256") { ([string]$state.toolchain_artifact_sha256).ToLowerInvariant() } else { "" }
  return [pscustomobject]@{ Version = [string]$state.toolchain_version; Sha256 = $sha }
}

Install-Arlen -Version $Version -Prefix $Prefix -BinDir $BinDir -Archive $Archive -MsysRoot $MsysRoot
