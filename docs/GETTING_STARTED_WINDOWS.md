# Getting Started on Windows

`propane` refuses production startup on Windows (exit status 2); use `boomhauer`
for development. Its help remains available. Multiworker serving and rolling
reloads require a future shared-listener implementation.

Windows is supported for **development** from Arlen 0.3.0: install Arlen,
create apps, build them, and run them under `boomhauer` with watch mode.
Arlen runs on the [gnustep-cli](https://github.com/danjboyd/gnustep-cli-new)
managed MSYS2 `CLANG64` GNUstep toolchain.

Production on Windows (`propane`, `jobs-worker`, and service deploys) is not
supported yet; it is planned for 0.4.0. Deploy to Linux or macOS.

## 1. Install Arlen and the Toolchain

Use 64-bit Windows and Windows PowerShell 5.1, which ships with Windows.
Arlen is verified on Windows Server 2022 Standard (build 20348). Windows 10
and 11 use the same MSYS2 `CLANG64` stack and remain untested.

```powershell
irm https://github.com/danjboyd/Arlen/releases/latest/download/install.ps1 | iex
arlen new MyApp
cd MyApp
arlen boomhauer --port 3000
```

The installer downloads the prebuilt Windows archive, verifies its SHA256SUMS
entry, and installs the matching gnustep-cli toolchain automatically when
needed. The toolchain download is about 1.1 GB and includes clang, GNUstep,
libdispatch and libcurl. No administrator rights are required for the default
user installation. Arlen ships libpq in `build\dll`; no PostgreSQL client
installation is needed. Nothing in the framework is compiled during install;
your applications compile locally.

The installer prepends its launcher directory to both the current process PATH
and persistent user PATH, without duplicates. `irm | iex` and `& .\install.ps1`
make bare `arlen` available immediately in that PowerShell session. If you run
the installer in a child process with `powershell -File`, open a new terminal
afterwards: a child process cannot change its parent's environment. Existing
terminal processes retain their prior environment. New terminals inherit the
saved user PATH.

To pin the Arlen release:

```powershell
& ([scriptblock]::Create((irm https://github.com/danjboyd/Arlen/releases/latest/download/install.ps1))) -Version 0.3.0
```

The `latest` URL selects the latest **published** release. An unpublished
candidate must be tested with a local installer and `-Archive`; the example
above does not imply that 0.3.0 assets are already published.

## 2. Installation Options and Recovery

The install root defaults to `%LOCALAPPDATA%\Arlen`. Releases are kept in
separate directories and `current` is a junction to the active one. The
`bin\arlen.cmd` launcher enters the matching `CLANG64` environment, exports
`ARLEN_FRAMEWORK_ROOT`, and works from PowerShell or cmd.exe outside the checkout.
Install and app directories may contain spaces; keep them short to avoid
Windows' default path-length limit.

- `-Version X.Y.Z`: release to install (default: latest published release).
- `-Prefix DIR`: install root (default `%LOCALAPPDATA%\Arlen`).
- `-BinDir DIR`: launcher directory (default `<Prefix>\bin`).
- `-Archive FILE`: use a local Windows zip. Verify a downloaded zip against
  its release's SHA256SUMS yourself; this option trusts the local archive.
- `-MsysRoot DIR`: explicitly select the managed toolchain root, including
  where to provision it when missing.
- `-NoSetup`: never download or execute prerequisite setup. Requires an
  already matching toolchain. Combine with `-Archive` for offline installation.
- `-NoPathUpdate`: skip persistent user PATH changes. The current process
  still receives the launcher directory for immediate use.

Arlen 0.3.0 requires gnustep-cli 0.1.1 and the exact toolchain artifact digest
recorded in its archive. Automatic setup uses the pinned upstream release
manifest and a SHA256-pinned PowerShell bootstrap. Unknown toolchain pins fail
with manual setup guidance. A root without matching state also needs setup;
an arbitrary GNUstep/MSYS2 installation is not enough.

For manual prerequisite installation:

```powershell
iwr https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.1/gnustep-bootstrap.ps1 -OutFile gnustep-bootstrap.ps1
powershell -ExecutionPolicy Bypass -File .\gnustep-bootstrap.ps1 setup --user --manifest https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.1/release-manifest.json
& .\install.ps1 -Archive .\arlen-0.3.0-windows-x64.zip -NoSetup
```

Never run `pacman -Sy` or `pacman -Syu` in the managed toolchain. Partial
upgrades break its clang, Python and GNUstep compatibility. Use the published
gnustep-cli bootstrap to repair or update it.

A failed download, checksum check or prerequisite setup leaves the active
Arlen installation intact. Correct the error and rerun the same command.
Reinstalling the same version stages a new directory with an `-install-`
suffix, retaining the old tree so running applications keep their files.
Previous trees are retained for manual cleanup after those applications stop.
The installer rejects a `current` path that is not a junction.

To run a downloaded installer, use `Unblock-File .\install.ps1` then
`& .\install.ps1`, or use `powershell -ExecutionPolicy Bypass -File` and open
a fresh terminal afterwards. The default `RemoteSigned` policy blocks
downloaded scripts until unblocked.

## 3. Create and Run an App

```powershell
arlen doctor
arlen new MyApp
cd MyApp
arlen boomhauer --port 3000
```

Open <http://localhost:3000/>. `boomhauer` rebuilds and restarts the app when
you change its sources, and shows build errors in the browser. The app binary
is `.boomhauer\build\boomhauer-app.exe`. Press Ctrl-C, or close the window,
to stop `boomhauer` and the app together.

`arlen test --app` builds and runs the app's XCTest bundle, as on Linux and
macOS.

## 4. Work From a Source Checkout

To change the framework itself or run its test suites, work from a checkout.
Clone it with Git for Windows, with line-ending conversion turned off:

```powershell
git clone -c core.autocrlf=false --recursive https://github.com/danjboyd/Arlen.git
cd Arlen
powershell -ExecutionPolicy Bypass -File scripts\run_clang64.ps1
```

`scripts\run_clang64.ps1` opens a `CLANG64` bash shell in the checkout, with
the GNUstep environment loaded. Inside it:

```sh
make all          # about 1.5 minutes on an 8-vCPU VM
./bin/arlen doctor
```

To run one command without an interactive shell:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_clang64.ps1 -InnerCommand "make all"
```

`run_clang64.ps1` looks for the toolchain in this order: `ARLEN_MSYS_ROOT`,
`%LOCALAPPDATA%\gnustep-cli`, `%ProgramFiles%\gnustep-cli`, then a stock MSYS2
at `C:\msys64`. The installed `arlen` launcher checks `ARLEN_MSYS_ROOT`, then
the toolchain the installer found, then the two gnustep-cli locations, and
passes the one it uses on to `boomhauer` and your app.

The repository's `.gitattributes` keeps shell scripts and makefiles on LF line
endings, but it doesn't apply to the submodules under `vendor/`. With Git for
Windows' default `core.autocrlf=true`, those would check out with CRLF line
endings, which break bash. That's why the clone above sets
`core.autocrlf=false`. To fix an existing clone, which may predate
`.gitattributes`, re-check it out without CRLF conversion:

```powershell
git config core.autocrlf false
git rm --cached -r -q . ; git reset --hard
git submodule foreach "git config core.autocrlf false; git rm --cached -r -q . ; git reset --hard"
```

More detail on the `CLANG64` lanes and the packaged-release contract is in
[Windows CLANG64](WINDOWS_CLANG64.md).

## 5. Known Limits

- **Production:** `propane`, `jobs-worker` and `arlen deploy` targets are not
  supported on Windows until 0.4.0.
- **Repository-root `boomhauer`:** running `boomhauer` from the framework
  checkout root is not supported on Windows yet. Run it from an app root.
- **Paths:** Windows long paths are off by default. Keep install roots and
  app directories short; `%LOCALAPPDATA%\Arlen` is fine.
- **Symlinks:** a standard user cannot create symlinks on Windows. Arlen uses
  junctions instead, for example `%LOCALAPPDATA%\Arlen\current`.
- **Stopping the server:** Ctrl-C and closing the window stop `boomhauer` and
  the app. Force-killing the console host (`conhost.exe` in Task Manager)
  does not, because Windows sends no close event; end `boomhauer-app.exe`
  there too.
- **First run:** the first command in a new MSYS2 home prints "MSYS2 is
  starting for the first time" while it copies skeleton files. That is
  harmless.

## 6. Read Next

- [First App Guide](FIRST_APP_GUIDE.md)
- [Windows CLANG64](WINDOWS_CLANG64.md)
- [CLI Reference](CLI_REFERENCE.md#windows-installer-toolsinstallps1)
- [Getting Started](GETTING_STARTED.md), the Linux guide, for the framework concepts that apply on every platform
