# CMX — Compressius Maximus

CMX is a local context-compression gateway for coding agents, with a terminal interface and usage dashboard.

## Install

Install CMX with npm or pnpm (Node.js 18+):

```sh
npm install --global @compressius/cmx
# or
pnpm add --global @compressius/cmx
```

Run `cmx login` to pair your CMX account, then use CONFIG to select your coding agent and provider. Your coding agent manages its own provider credentials.

The package supports Windows, macOS, and Linux on x64 and ARM64. It downloads the matching release binary and verifies its SHA-256 checksum. Documentation and your dashboard are at [compressi.us](https://compressi.us).

The `latest` npm tag tracks stable CMX releases. Each package downloads the matching release binary and verifies its SHA-256 before exposing `cmx`.

This repository distributes the installers and compiled releases. Application source and build tooling are maintained separately. Only `install.sh`, `install.ps1`, `install-testy.sh`, `install-nightly.sh`, `install-nightly.ps1`, and `README.md` belong in its Git tree.
