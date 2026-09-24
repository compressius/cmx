# CMX — Compressius Maximus

CMX is a local context-compression gateway for coding agents, with a terminal interface and usage dashboard.

## Install

Install CMX with npm or pnpm (Node.js 18+):

```sh
npm install --global @compressius/cmx
# or
pnpm add --global @compressius/cmx
```

After installation, run `cmx setup --ask-connect-ready` in an interactive terminal. CMX asks before connecting detected coding clients. You can use the local gateway without a CMX account; run `cmx login` only if you want the account dashboard and detailed statistics. Your coding client manages its own provider credentials.

The package supports Windows, macOS, and Linux on x64 and ARM64. It downloads the matching release binary and verifies its SHA-256 checksum. Documentation and your dashboard are at [compressi.us](https://compressi.us).

The `latest` npm tag tracks stable CMX releases. Each package downloads the matching release binary and verifies its SHA-256 before exposing `cmx`.

CMX is distributed under the Proprietary Gratis License. See `LICENSE` for the exact terms.

This repository distributes the installers and compiled releases. Application source and build tooling are maintained separately. Only `install.sh`, `install.ps1`, `install-testy.sh`, `install-nightly.sh`, `install-nightly.ps1`, `README.md`, and `LICENSE` belong in its Git tree.
