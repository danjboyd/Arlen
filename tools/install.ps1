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
  -NoSetup         require an already matching toolchain; never provision it
  -NoPathUpdate    skip persistent user PATH registration

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
  [string]$MsysRoot = "",
  [switch]$NoSetup,
  [switch]$NoPathUpdate
)

function Install-Arlen {
  param(
    [string]$Version,
    [string]$Prefix,
    [string]$BinDir,
    [string]$Archive,
    [string]$MsysRoot,
    [switch]$NoSetup,
    [switch]$NoPathUpdate
  )

  Set-StrictMode -Version Latest
  $ErrorActionPreference = "Stop"
  # Invoke-WebRequest's progress bar slows 5.1 downloads by an order of magnitude.
  $ProgressPreference = "SilentlyContinue"

  $repoSlug = "danjboyd/Arlen"
  # gnustep-cli publishes each toolchain version, with its PowerShell bootstrap
  # as a release asset, under the release tag of the same name. 0.1.1 is the
  # first toolchain Arlen's Windows support runs on. When the toolchain lives
  # outside the default root, the command names that root with --root, so
  # following it updates the toolchain this installer found.
  function BootstrapSetup([string]$ToolchainVersion, [string]$Root) {
    if (-not $ToolchainVersion) { $ToolchainVersion = "0.1.1" }
    $rootArgument = ""
    $defaultRoot = if ($env:LOCALAPPDATA) { [IO.Path]::Combine($env:LOCALAPPDATA, "gnustep-cli") } else { "" }
    if ($Root -and -not [string]::Equals($Root.TrimEnd('\'), $defaultRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
      $rootArgument = " --root `"$($Root.TrimEnd('\'))`""
    }
    return "iwr https://github.com/danjboyd/gnustep-cli-new/releases/download/v$ToolchainVersion/gnustep-bootstrap.ps1 -OutFile gnustep-bootstrap.ps1`n" +
      "  powershell -ExecutionPolicy Bypass -File .\gnustep-bootstrap.ps1 setup --user$rootArgument --manifest https://github.com/danjboyd/gnustep-cli-new/releases/download/v$ToolchainVersion/release-manifest.json"
  }
  function Say([string]$Message) { Write-Host "arlen-install: $Message" }
  function Die([string]$Message) { throw "arlen-install: error: $Message" }

  if (-not $Prefix) { $Prefix = Join-Path $env:LOCALAPPDATA "Arlen" }
  if (-not $BinDir) { $BinDir = Join-Path $Prefix "bin" }
  $Prefix = [IO.Path]::GetFullPath($Prefix)
  $BinDir = [IO.Path]::GetFullPath($BinDir)
  $Version = $Version -replace '^v', ''

  if (-not [Environment]::Is64BitOperatingSystem) {
    Die "Arlen's Windows release is x64 only"
  }

  # FileShare.None serializes even separate PowerShell processes/sessions.
  # Keep the empty lock file: OS handle lifetime determines lock ownership.
  $prefixLockPath = $Prefix.TrimEnd('\') + '.install.lock'
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($prefixLockPath)) | Out-Null
  try { $prefixLock = [IO.File]::Open($prefixLockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
  catch { Die "another installer owns $prefixLockPath, or the lock cannot be opened: $($_.Exception.Message)" }
  $binLock = $null
  try {
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
  # An explicit root is authoritative, including when it needs provisioning.
  if ($MsysRoot) { $candidates = @($MsysRoot) }
  $resolvedRoot = $null
  foreach ($candidate in $candidates) {
    if ((Test-Path (Join-Path $candidate "usr\bin\env.exe")) -and
        (Test-Path (Join-Path $candidate "clang64\share\GNUstep\Makefiles\GNUstep.sh"))) {
      $resolvedRoot = [IO.Path]::GetFullPath($candidate)
      break
    }
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
    foreach ($required in @('bin\arlen', 'build\arlen.exe', 'build\boomhauer.exe', 'build\eocc.exe', 'build\lib\libArlenFramework.a', 'build\.release-prebuilt')) {
      if (-not (Test-Path -LiteralPath (Join-Path $top $required) -PathType Leaf)) { Die "archive lacks prebuilt $required" }
    }
    $Version = $dist["version"]

    # Resolve the required ABI from the verified archive before provisioning.
    $wantToolchain = $dist["toolchain"]
    $wantToolchainSha = $dist["toolchain_sha256"]
    if ($Version -notmatch '^\d+\.\d+\.\d+$') { Die "invalid archive version '$Version'" }
    if (-not $wantToolchain -or -not $wantToolchainSha) { Die "archive lacks pinned toolchain metadata" }
    $state = if ($resolvedRoot) { Get-GnustepToolchainState -Root $resolvedRoot } else { $null }
    $ready = $resolvedRoot -and $state -and $state.Version -eq $wantToolchain -and
      $state.Sha256 -eq $wantToolchainSha.ToLowerInvariant() -and
      (Test-Path (Join-Path $resolvedRoot "clang64\lib\libcurl.dll.a"))
    if (-not $ready) {
      $setupRoot = if ($resolvedRoot) { $resolvedRoot } elseif ($MsysRoot) { $MsysRoot } elseif ($env:ARLEN_MSYS_ROOT) { $env:ARLEN_MSYS_ROOT } else { Join-Path $env:LOCALAPPDATA "gnustep-cli" }
      $setupRoot = [IO.Path]::GetFullPath($setupRoot)
      if ($NoSetup) { Die "matching gnustep-cli toolchain $wantToolchain required at $setupRoot (-NoSetup). Run:`n$(BootstrapSetup $wantToolchain $setupRoot)" }
      # Pin the executable bootstrap as well as its release manifest. Future
      # toolchains require an explicit reviewed digest update here.
      if ($wantToolchain -ne "0.1.1" -or $wantToolchainSha.ToLowerInvariant() -ne "07d57993b2d5364578aff0392fede18d5a427f9f5dd22a03df1ec56c28f98dba") {
        Die "no automatic setup pin for toolchain $wantToolchain ($wantToolchainSha); provision it manually and use -NoSetup"
      }
      $bootstrapUrl = "https://github.com/danjboyd/gnustep-cli-new/releases/download/v$wantToolchain/gnustep-bootstrap.ps1"
      $bootstrapPath = Join-Path $workDir "gnustep-bootstrap.ps1"
      Say "installing gnustep-cli $wantToolchain at $setupRoot (about 1.1 GB download)"
      Invoke-WebRequest -UseBasicParsing -Uri $bootstrapUrl -OutFile $bootstrapPath
      if ((Get-FileHash -Algorithm SHA256 -LiteralPath $bootstrapPath).Hash.ToLowerInvariant() -ne "a41adbf84d38a6ae90f4bdbbe0b9c3e35136cb3ee695bf26b783c04972045034") { Die "gnustep-cli bootstrap checksum mismatch" }
      $beforeSetupPath = [Environment]::GetEnvironmentVariable('Path', 'User')
      try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bootstrapPath setup --user --root $setupRoot --manifest "https://github.com/danjboyd/gnustep-cli-new/releases/download/v$wantToolchain/release-manifest.json"
        $setupExit = $LASTEXITCODE
      } finally {
        # The upstream bootstrap registers its own bin directory too.
        if ($NoPathUpdate) { [Environment]::SetEnvironmentVariable('Path', $beforeSetupPath, 'User') }
      }
      if ($setupExit -ne 0) { Die "gnustep-cli setup failed (exit $setupExit); rerun the installer to retry" }
      $resolvedRoot = $setupRoot
      $state = Get-GnustepToolchainState -Root $resolvedRoot
      if (-not $state -or $state.Version -ne $wantToolchain -or $state.Sha256 -ne $wantToolchainSha.ToLowerInvariant() -or
          -not (Test-Path (Join-Path $resolvedRoot "usr\bin\env.exe")) -or
          -not (Test-Path (Join-Path $resolvedRoot "clang64\share\GNUstep\Makefiles\GNUstep.sh")) -or
          -not (Test-Path (Join-Path $resolvedRoot "clang64\lib\libcurl.dll.a"))) {
        Die "gnustep-cli setup did not produce the matching CLANG64 toolchain; existing Arlen installation was preserved"
      }
    }

    New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
    $dest = Join-Path $Prefix $Version
    # Never mutate an installed tree: a failed retry or a running app keeps
    # its existing files. Successful retries retain the previous install.
    if (Test-Path -LiteralPath $dest) { $dest += "-install-" + [Guid]::NewGuid().ToString("N").Substring(0, 8) }
    Move-Item -LiteralPath $top -Destination $dest
  } finally {
    if ([IO.Path]::GetFullPath($workDir).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
  $binLockPath = $BinDir.TrimEnd('\') + '.install.lock'
  if (-not [string]::Equals($binLockPath, $prefixLockPath, [StringComparison]::OrdinalIgnoreCase)) {
    try { $binLock = [IO.File]::Open($binLockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { Die "another installer owns $binLockPath, or the lock cannot be opened: $($_.Exception.Message)" }
  }
  $current = Join-Path $Prefix "current"
  $link = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
  if ($link -and $link.LinkType -ne 'Junction') { Die "$current is not a junction; refusing to replace it" }
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
$msysRoot = $null
foreach ($candidate in $candidates) {
  $probe = Join-Path $candidate "usr\bin\env.exe"
  if ((Test-Path $probe) -and (Test-Path (Join-Path $candidate "clang64\share\GNUstep\Makefiles\GNUstep.sh"))) {
    $envExe = $probe
    $msysRoot = $candidate
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
# Windows PowerShell 5.1 does not escape double quotes inside arguments to a
# native program, and env.exe parses its command line with the Windows rules,
# so escape them as \" or bash receives a broken script.
# Put this launcher in a Job Object that kills its members when the last handle
# closes. Windows does not end children with their parent, so without it,
# closing the console or ending this process left env.exe, bash and the
# server running (and holding the port). Children join the job automatically.
# The helper compiles once next to this script; failure only loses the cleanup.
try {
  if (-not ('ArlenLauncherJob1' -as [type])) {
    $jobDll = Join-Path $PSScriptRoot 'arlen-launcher-job1.dll'
    $jobSource = @"
using System;
using System.Runtime.InteropServices;
public static class ArlenLauncherJob1 {
  [StructLayout(LayoutKind.Sequential)] struct Basic {
    public long PerProcessUserTimeLimit; public long PerJobUserTimeLimit; public uint LimitFlags;
    public UIntPtr MinimumWorkingSetSize; public UIntPtr MaximumWorkingSetSize; public uint ActiveProcessLimit;
    public UIntPtr Affinity; public uint PriorityClass; public uint SchedulingClass;
  }
  [StructLayout(LayoutKind.Sequential)] struct IoCounters { public ulong R, W, O, RB, WB, OB; }
  [StructLayout(LayoutKind.Sequential)] struct Extended {
    public Basic BasicLimits; public IoCounters Io; public UIntPtr ProcessMemoryLimit;
    public UIntPtr JobMemoryLimit; public UIntPtr PeakProcessMemoryUsed; public UIntPtr PeakJobMemoryUsed;
  }
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr attributes, string name);
  [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref Extended info, uint length);
  [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  static IntPtr job;  // held until this process exits; closing it kills the tree
  public static bool KillTreeOnExit() {
    job = CreateJobObject(IntPtr.Zero, null);
    if (job == IntPtr.Zero) return false;
    Extended info = new Extended();
    info.BasicLimits.LimitFlags = 0x2000;  // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    if (!SetInformationJobObject(job, 9, ref info, (uint)Marshal.SizeOf(typeof(Extended)))) return false;
    return AssignProcessToJobObject(job, GetCurrentProcess());
  }
}
"@
    if (-not (Test-Path -LiteralPath $jobDll)) {
      try { Add-Type -TypeDefinition $jobSource -OutputAssembly $jobDll -OutputType Library } catch { }
    }
    if (Test-Path -LiteralPath $jobDll) { Add-Type -Path $jobDll } else { Add-Type -TypeDefinition $jobSource }
  }
  [void][ArlenLauncherJob1]::KillTreeOnExit()
} catch {
}
$nativeArgs = @($args | ForEach-Object { ([string]$_).Replace('"', '\"') })
# ARLEN_MSYS_ROOT tells the Arlen runtime (boomhauer's helper bash, the app)
# which toolchain this launcher chose; without it a non-default root would
# fall back to %LOCALAPPDATA%\gnustep-cli. Passed through env.exe so it is
# scoped to this run and never set in the caller's shell.
& $envExe 'MSYSTEM=CLANG64' 'CHERE_INVOKING=1' "ARLEN_HOME_WIN=$arlenHome" "ARLEN_MSYS_ROOT=$msysRoot" '/usr/bin/bash' '-lc' $bootstrap.Replace('"', '\"') 'arlen' @nativeArgs
exit $LASTEXITCODE
'@
  $launcherBody = $launcherBody.Replace('__CURRENT__', $current.Replace("'", "''")).Replace('__MSYS_ROOT__', $resolvedRoot.Replace("'", "''"))
  $cmdBody = "@echo off`r`n" +
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0arlen-clang64.ps1`" %*`r`n" +
    "exit /b %ERRORLEVEL%`r`n"
  $transaction = [Guid]::NewGuid().ToString('N')
  $stagedCurrent = Join-Path $Prefix ('.current-install-' + $transaction)
  $backupCurrent = Join-Path $Prefix ('.current-old-' + $transaction)
  $launchers = @(
    @{ Path=$launcherPs1; Stage=($launcherPs1 + '.' + $transaction + '.new'); Backup=($launcherPs1 + '.' + $transaction + '.old'); Body=$launcherBody; Encoding=(New-Object Text.UTF8Encoding $false); OriginalMoved=$false; Installed=$false },
    @{ Path=$launcherCmd; Stage=($launcherCmd + '.' + $transaction + '.new'); Backup=($launcherCmd + '.' + $transaction + '.old'); Body=$cmdBody; Encoding=(New-Object Text.ASCIIEncoding); OriginalMoved=$false; Installed=$false }
  )
  $oldCurrentMoved = $false
  $newCurrentInstalled = $false
  $committed = $false
  try {
    # Stage all writes and junction creation before touching working launchers.
    foreach ($entry in $launchers) { Write-ArlenLauncherStage $entry.Stage $entry.Body $entry.Encoding }
    New-Item -ItemType Junction -Path $stagedCurrent -Target $dest | Out-Null
    foreach ($entry in $launchers) {
      if ([IO.File]::Exists($entry.Path)) {
        [IO.File]::Move($entry.Path, $entry.Backup)
        $entry.OriginalMoved = $true
      }
      Move-ArlenActivationFile $entry.Stage $entry.Path
      $entry.Installed = $true
    }
    if ($link) {
      [IO.Directory]::Move($current, $backupCurrent)
      $oldCurrentMoved = $true
    }
    Move-ArlenActivationJunction $stagedCurrent $current
    $newCurrentInstalled = $true
    $committed = $true
  } catch {
    $activationError = $_
    $rollbackErrors = @()
    try {
      if ($newCurrentInstalled) { [IO.Directory]::Delete($current) }
      if ($oldCurrentMoved) { [IO.Directory]::Move($backupCurrent, $current) }
    } catch { $rollbackErrors += "junction: $_" }
    for ($index = $launchers.Count - 1; $index -ge 0; $index--) {
      $entry = $launchers[$index]
      try {
        if ($entry.Installed) { [IO.File]::Delete($entry.Path) }
        if ($entry.OriginalMoved) { [IO.File]::Move($entry.Backup, $entry.Path) }
      } catch { $rollbackErrors += "$($entry.Path): $_" }
    }
    if ($rollbackErrors.Count) { Die "activation failed ($activationError); rollback incomplete, preserve .old backups: $($rollbackErrors -join '; ')" }
    Die "activation failed; previous launchers and current junction restored: $activationError"
  } finally {
    # Unlink checked transaction junctions only; never recurse into releases.
    foreach ($entry in $launchers) {
      if ([IO.File]::Exists($entry.Stage)) { [IO.File]::Delete($entry.Stage) }
      if ($committed -and [IO.File]::Exists($entry.Backup)) { [IO.File]::Delete($entry.Backup) }
    }
    if (Get-Item -LiteralPath $stagedCurrent -Force -ErrorAction SilentlyContinue) { [IO.Directory]::Delete($stagedCurrent) }
    if ($committed -and $oldCurrentMoved) { [IO.Directory]::Delete($backupCurrent) }
  }
  Say "installed Arlen $Version at $dest"
  Say "toolchain: $resolvedRoot"
  Say "launcher: $launcherCmd"
  if (-not $NoPathUpdate) {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $userEntries = @($userPath -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ine $BinDir.TrimEnd('\') })
    [Environment]::SetEnvironmentVariable("Path", ((@($BinDir) + $userEntries) -join ';'), "User")
  }
  # Script invocation and irm | iex both update the caller's process environment.
  # A child powershell -File cannot update its parent; it must open a new shell.
  $processEntries = @($env:Path -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ine $BinDir.TrimEnd('\') })
  $env:Path = (@($BinDir) + $processEntries) -join ';'
  Say "arlen is available in this process; new terminals use the saved user PATH unless -NoPathUpdate was passed"
  Write-Host ""
  Write-Host "Next:"
  Write-Host "  arlen doctor"
  Write-Host "  arlen new MyApp; cd MyApp; arlen boomhauer --port 3000"
  } finally {
    if ($binLock) { $binLock.Dispose() }
    $prefixLock.Dispose()
  }
}

# Small filesystem boundaries keep fault-injection tests on the actual
# activation algorithm, without adding installer test flags to the CLI.
function Write-ArlenLauncherStage($Path, $Body, $Encoding) { [IO.File]::WriteAllText($Path, $Body, $Encoding) }
function Move-ArlenActivationFile($Source, $Destination) { [IO.File]::Move($Source, $Destination) }
function Move-ArlenActivationJunction($Source, $Destination) { [IO.Directory]::Move($Source, $Destination) }

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

Install-Arlen -Version $Version -Prefix $Prefix -BinDir $BinDir -Archive $Archive -MsysRoot $MsysRoot -NoSetup:$NoSetup -NoPathUpdate:$NoPathUpdate
