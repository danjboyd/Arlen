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
iwr https://raw.githubusercontent.com/danjboyd/gnustep-cli-new/v0.1.0/scripts/bootstrap/gnustep-bootstrap.ps1 -OutFile gnustep-bootstrap.ps1
powershell -ExecutionPolicy Bypass -File .\gnustep-bootstrap.ps1 setup --user --manifest https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0/release-manifest.json
```

This command is provisional. A future gnustep-cli release will publish the
bootstrap script as a release asset with its own download URL.

Arlen links libcurl, which the toolchain does not ship yet. Install it inside
the toolchain:

```powershell
& "$env:LOCALAPPDATA\gnustep-cli\usr\bin\bash.exe" -lc 'pacman -S --noconfirm --needed mingw-w64-clang-x86_64-curl'
```

> **Never run `pacman -Sy` or `pacman -Syu` in the managed toolchain.**
> Refreshing the package database causes partial upgrades that break it. A
> newer python breaks `pyexpat` against the shipped expat, and a newer clang
> breaks the GNUstep headers. Use plain `pacman -S` as shown, and install
> nothing else into the managed root unless these docs say to.

Optional, for PostgreSQL apps only: install libpq the same way, with plain
`pacman -S` and never `-Sy`/`-Syu`:

```powershell
& "$env:LOCALAPPDATA\gnustep-cli\usr\bin\bash.exe" -lc 'pacman -S --noconfirm --needed mingw-w64-clang-x86_64-postgresql'
```

Arlen loads `libpq-5.dll` from the toolchain at runtime. Without it, apps
build but fail when they first connect to PostgreSQL.

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
installer stops and tells you to rerun the gnustep-cli bootstrap `setup`.

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
is `.boomhauer\build\boomhauer-app.exe`.

## 4. Work From a Source Checkout

To change the framework itself or run its test suites, work from a checkout.
Clone it with Git for Windows:

```powershell
git clone --recursive https://github.com/danjboyd/Arlen.git
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

`run_clang64.ps1` and the `arlen` launcher look for the toolchain in this
order: `ARLEN_MSYS_ROOT`, `%LOCALAPPDATA%\gnustep-cli`,
`%ProgramFiles%\gnustep-cli`, then a stock MSYS2 at `C:\msys64`.

The repository's `.gitattributes` keeps shell scripts and makefiles on LF line
endings, whatever `core.autocrlf` is set to. A clone made before that file
existed may have CRLF scripts that break bash. Clone again to fix it.

More detail on the `CLANG64` lanes and the packaged-release contract is in
[Windows CLANG64](WINDOWS_CLANG64.md).

## 5. Known Limits

- **Production:** `propane`, `jobs-worker` and `arlen deploy` targets are not
  supported on Windows until 0.4.0.
- **Paths:** Windows long paths are off by default. Keep install roots and
  app directories short; `%LOCALAPPDATA%\Arlen` is fine.
- **Symlinks:** a standard user cannot create symlinks on Windows. Arlen uses
  junctions instead, for example `%LOCALAPPDATA%\Arlen\current`.
- **First run:** the first command in a new MSYS2 home prints "MSYS2 is
  starting for the first time" while it copies skeleton files. That is
  harmless.
- **Quoting:** Windows PowerShell 5.1 can mangle double quotes embedded in
  arguments passed to `arlen`. Prefer plain arguments, or use single quotes
  around the whole argument.

## 6. Read Next

- [First App Guide](FIRST_APP_GUIDE.md)
- [Windows CLANG64](WINDOWS_CLANG64.md)
- [CLI Reference](CLI_REFERENCE.md#windows-installer-toolsinstallps1)
- [Getting Started](GETTING_STARTED.md), the Linux guide, for the framework concepts that apply on every platform
