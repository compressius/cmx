#!/bin/sh
set -e

# CMX Install Script
# Usage: curl -sSfL https://compressi.us/install.sh | sh

REPO="${CMX_RELEASE_REPO:-compressius/cmx}"
VERSION="${CMX_VERSION:-latest}"

if [ -n "${CMX_INSTALL_DIR:-}" ]; then
  INSTALL_DIR="$CMX_INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
elif [ -w "/usr/local/bin" ]; then
  INSTALL_DIR="/usr/local/bin"
elif [ -n "$HOME" ]; then
  INSTALL_DIR="$HOME/.local/bin"
  mkdir -p "$INSTALL_DIR"
else
  INSTALL_DIR="/usr/local/bin"
fi

# Detect OS and architecture
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64|amd64)  ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)
    echo "Error: Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

case "$OS" in
  linux|darwin) ;;
  *)
    echo "Error: Unsupported OS: $OS"
    echo "For Windows, download the binary manually from GitHub releases."
    exit 1
    ;;
esac

echo "Installing CMX for ${OS}/${ARCH}..."

# Determine download URL
if [ "$VERSION" = "latest" ]; then
  DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/cmx-${OS}-${ARCH}"
else
  DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/cmx-${OS}-${ARCH}"
fi

# Create temp directory
TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'cmx')"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

# Download
echo "Downloading cmx-${OS}-${ARCH} from ${REPO} (${VERSION})..."
DOWNLOAD_SUCCESS=0

# Interactive terminals get curl's transfer bar; piped output stays plain.
curl_download() {
  if [ -t 2 ]; then
    curl --fail --show-error --location --progress-bar "$@"
  else
    curl --fail --silent --show-error --location "$@"
  fi
}

# Prefer the visible transfer over gh's silent release download when attached
# to a terminal, so the user always sees download progress.
if [ -t 2 ] && command -v curl >/dev/null 2>&1; then
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl_download -H "Authorization: token ${GITHUB_TOKEN}" -o "${TMP_DIR}/cmx" "$DOWNLOAD_URL" && DOWNLOAD_SUCCESS=1
  else
    curl_download -o "${TMP_DIR}/cmx" "$DOWNLOAD_URL" && DOWNLOAD_SUCCESS=1
  fi
fi

if [ "$DOWNLOAD_SUCCESS" -ne 1 ] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  if [ "$VERSION" = "latest" ]; then
    if gh release download -p "cmx-${OS}-${ARCH}" -O "${TMP_DIR}/cmx" --repo "$REPO" >/dev/null 2>&1; then
      DOWNLOAD_SUCCESS=1
    fi
  else
    if gh release download "$VERSION" -p "cmx-${OS}-${ARCH}" -O "${TMP_DIR}/cmx" --repo "$REPO" >/dev/null 2>&1; then
      DOWNLOAD_SUCCESS=1
    fi
  fi
fi

if [ "$DOWNLOAD_SUCCESS" -ne 1 ]; then
  if command -v curl >/dev/null 2>&1; then
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      if curl_download -H "Authorization: token ${GITHUB_TOKEN}" -o "${TMP_DIR}/cmx" "$DOWNLOAD_URL"; then
        DOWNLOAD_SUCCESS=1
      fi
    else
      if curl_download -o "${TMP_DIR}/cmx" "$DOWNLOAD_URL"; then
        DOWNLOAD_SUCCESS=1
      fi
    fi
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      if wget -q --header="Authorization: token ${GITHUB_TOKEN}" -O "${TMP_DIR}/cmx" "$DOWNLOAD_URL"; then
        DOWNLOAD_SUCCESS=1
      fi
    else
      if wget -qO "${TMP_DIR}/cmx" "$DOWNLOAD_URL"; then
        DOWNLOAD_SUCCESS=1
      fi
    fi
  fi
fi

if [ "$DOWNLOAD_SUCCESS" -ne 1 ]; then
  echo "Error: Download failed. If this is a private repository, run 'gh auth login' or set GITHUB_TOKEN."
  exit 1
fi

# This is a truthful terminal-native progress result: it reports bytes that
# were actually written, without a spinner, timer-derived percentage, or a
# continuously redrawn progress bar. It is equally safe when stdout is piped.
DOWNLOADED_BYTES="$(wc -c < "${TMP_DIR}/cmx" | tr -d '[:space:]')"
echo "Downloaded ${DOWNLOADED_BYTES} bytes."
echo "Verifying release checksum..."

# Verify the downloaded artifact against the release checksum before executing it.
CHECKSUM_URL="https://github.com/${REPO}/releases/download/${VERSION}/SHA256SUMS"
if [ "$VERSION" = "latest" ]; then
  CHECKSUM_URL="https://github.com/${REPO}/releases/latest/download/SHA256SUMS"
fi
CHECKSUM_SUCCESS=0
if command -v curl >/dev/null 2>&1; then
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -sSfL -H "Authorization: token ${GITHUB_TOKEN}" -o "${TMP_DIR}/SHA256SUMS" "$CHECKSUM_URL" && CHECKSUM_SUCCESS=1
  else
    curl -sSfL -o "${TMP_DIR}/SHA256SUMS" "$CHECKSUM_URL" && CHECKSUM_SUCCESS=1
  fi
elif command -v wget >/dev/null 2>&1; then
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    wget -q --header="Authorization: token ${GITHUB_TOKEN}" -O "${TMP_DIR}/SHA256SUMS" "$CHECKSUM_URL" && CHECKSUM_SUCCESS=1
  else
    wget -qO "${TMP_DIR}/SHA256SUMS" "$CHECKSUM_URL" && CHECKSUM_SUCCESS=1
  fi
fi
if [ "$CHECKSUM_SUCCESS" -ne 1 ]; then
  echo "Error: Release checksum download failed"
  exit 1
fi
if command -v sha256sum >/dev/null 2>&1; then
  expected="$(grep "  cmx-${OS}-${ARCH}$" "${TMP_DIR}/SHA256SUMS" | awk '{print $1}')"
  actual="$(sha256sum "${TMP_DIR}/cmx" | awk '{print $1}')"
  [ -n "$expected" ] && [ "$expected" = "$actual" ]
elif command -v shasum >/dev/null 2>&1; then
  expected="$(grep "  cmx-${OS}-${ARCH}$" "${TMP_DIR}/SHA256SUMS" | awk '{print $1}')"
  actual="$(shasum -a 256 "${TMP_DIR}/cmx" | awk '{print $1}')"
  [ -n "$expected" ] && [ "$expected" = "$actual" ]
else
  echo "Error: sha256sum or shasum is required to verify the release"
  exit 1
fi

chmod +x "${TMP_DIR}/cmx"

# Verify the binary runs
if ! "${TMP_DIR}/cmx" --version >/dev/null 2>&1; then
  echo "Error: Downloaded binary failed to execute"
  exit 1
fi

CMX_VERSION_STR="$("${TMP_DIR}/cmx" --version)"

# Install
echo "Installing verified binary..."
if [ -w "$INSTALL_DIR" ]; then
  mv "${TMP_DIR}/cmx" "${INSTALL_DIR}/cmx"
else
  echo "Installing to ${INSTALL_DIR} (requires sudo)..."
  sudo mv "${TMP_DIR}/cmx" "${INSTALL_DIR}/cmx"
fi

echo ""
echo "✓ ${CMX_VERSION_STR} installed to ${INSTALL_DIR}/cmx"
echo ""

case ":$PATH:" in
  *:"$INSTALL_DIR":*) ;;
  *) echo "Notice: ${INSTALL_DIR} is not in your PATH. Add it to your ~/.bashrc or ~/.zshrc:"
     echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
     echo ""
     ;;
esac

if [ "${CMX_SKIP_START:-0}" != "1" ]; then
  if ! "${INSTALL_DIR}/cmx" setup; then
    echo "Automatic setup could not finish. If sign-in is required, run cmx login; successful login completes setup automatically."
    exit 1
  fi
  "${INSTALL_DIR}/cmx" harness enable >/dev/null 2>&1 || true
fi
