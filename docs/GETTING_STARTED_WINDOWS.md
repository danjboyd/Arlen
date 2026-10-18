# Getting Started on Windows

Windows is supported for **development** from Arlen 0.3.0: install Arlen,
create apps, build them, and run them under `boomhauer` with watch mode.
Arlen runs on the [gnustep-cli](https://github.com/danjboyd/gnustep-cli-new)
managed MSYS2 `CLANG64` GNUstep toolchain.

Production on Windows (`propane`, `jobs-worker`, and service deploys) is not
supported yet; it is planned for 0.4.0. Deploy to Linux or macOS.

## 1. Install the Toolchain

You need 64-bit Windows and Windows PowerShell 5.1, which ships with Windows.
Arlen is verified on Windows Server 2022 Standard (build 20348). Windows 10
and 11 use the same MSYS2 `CLANG64` stack and should work, but are untested.

Install the gnustep-cli managed toolchain for your user. It is a full MSYS2
tree with clang, GNUstep and libdispatch, and it installs to
`%LOCALAPPDATA%\gnustep-cli` without administrator rights:

```powershell
iwr https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.1/gnustep-bootstrap.ps1 -OutFile gnustep-bootstrap.ps1
powershell -ExecutionPolicy Bypass -File .\gnustep-bootstrap.ps1 setup --user --manifest https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.1/release-manifest.json
```

Arlen 0.3.0 needs gnustep-cli `v0.1.1`. The toolchain includes everything
Arlen links against, libcurl among them, so there is nothing else to install.
If you already have the `v0.1.0` toolchain, rerun the command above to move
to `v0.1.1`; the Arlen installer refuses a toolchain version that differs
from the one its release was built with.

> **Never run `pacman -Sy` or `pacman -Syu` in the managed toolchain.**
> Refreshing the package database causes partial upgrades that break it. A
> newer python breaks `pyexpat` against the shipped expat, and a newer clang
> breaks the GNUstep headers. Install nothing into the managed root yourself.

You don't need to install a PostgreSQL client. The Arlen release ships libpq
as `build\dll\libpq.dll`, and Arlen loads it from the install. Its other
dependencies are already in the toolchain.

## 2. Install Arlen

```powershell
irm https://github.com/danjboyd/Arlen/releases/latest/download/install.ps1 | iex
```

To pin a release, pass `-Version`:

```powershell
& ([scriptblock]::Create((irm https://github.com/danjboyd/Arlen/releases/latest/download/install.ps1))) -Version 0.3.0
```

The installer downloads `arlen-X.Y.Z-windows-x64.zip` and checks it against
the release's `SHA256SUMS`. The zip has prebuilt framework tools (`arlen.exe`,
`boomhauer.exe`, `eocc.exe` and `libArlenFramework.a`), so nothing in the
framework is compiled at install time. Your apps are still compiled on your
machine.

The prebuilt tools are tied to the toolchain they were built with. If your
toolchain's version differs from the one the release was built against, the
installer stops and prints the gnustep-cli bootstrap `setup` command to run
(with `--root` if your toolchain is not in the default location).

The installer unpacks to `%LOCALAPPDATA%\Arlen\<version>`, points the
`%LOCALAPPDATA%\Arlen\current` junction at it, and writes an `arlen.cmd`
launcher to `%LOCALAPPDATA%\Arlen\bin`. The launcher works from both cmd.exe
and PowerShell. It enters the `CLANG64` environment and sets
`ARLEN_FRAMEWORK_ROOT` to the install, so apps can live anywhere.

If `arlen` is not found, add the launcher directory to your user `PATH`, then
open a new terminal:

```powershell
[Environment]::SetEnvironmentVariable('Path', "$env:LOCALAPPDATA\Arlen\bin;" + [Environment]::GetEnvironmentVariable('Path', 'User'), 'User')
```

Installer options:

- `-Version X.Y.Z`: release to install (default: the latest release)
- `-Prefix DIR`: install root (default `%LOCALAPPDATA%\Arlen`)
- `-BinDir DIR`: launcher directory (default `<Prefix>\bin`)
- `-Archive FILE`: install a downloaded `arlen-X.Y.Z-windows-x64.zip` instead
- `-MsysRoot DIR`: the toolchain root, if it is not in a default location

To run a downloaded copy of `install.ps1` instead of piping it, use
`powershell -ExecutionPolicy Bypass -File install.ps1`, or run `Unblock-File`
on it first. The default `RemoteSigned` policy blocks downloaded scripts.

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
