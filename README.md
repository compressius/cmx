# CMX — Compressius Maximus

CMX is a local context-compression gateway for coding agents, with a terminal interface and usage dashboard.

## Install

Linux and macOS, on Intel/AMD 64-bit or ARM64:

```sh
curl -sSfL https://raw.githubusercontent.com/administrakt0r/cmx/main/install.sh | sh
```

Run `cmx login` to pair your CMX account, then use CONFIG to select your coding agent and provider. Your coding agent manages its own provider credentials.

Windows x64 and ARM64: download **CMX Setup (.exe)** from [compressi.us/downloads](https://compressi.us/downloads), open it, and press Enter to install for your user account. Setup adds a Start menu shortcut and guides account pairing. No administrator access is required. The setup executable and PowerShell script are unsigned; Windows may display a publisher warning.

For PowerShell users, download [install.ps1](https://compressi.us/install.ps1), review it, then run `powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1`. Nightly testers can use [install-nightly.ps1](https://compressi.us/install-nightly.ps1). Both scripts verify the release binary's SHA-256 before installing. Close CMX before upgrading. Windows service auto-start is not installed.

Downloads and checksums are available on the [releases page](https://github.com/administrakt0r/cmx/releases). Documentation and your dashboard are at [compressi.us](https://compressi.us).

This repository distributes the installers and compiled releases. Application source and build tooling are maintained separately. Only `install.sh`, `install-nightly.sh`, `install.ps1`, `install-nightly.ps1`, and `README.md` belong in its Git tree.
