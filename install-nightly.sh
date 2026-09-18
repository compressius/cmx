#!/bin/sh
set -e

# CMX Install Script
# Usage: curl -sSfL https://compressi.us/install-nightly.sh | sh

REPO="${CMX_RELEASE_REPO:-compressius/cmx}"
VERSION="${CMX_VERSION:-v0.2.17-nightly.20260918004205.6123f862fcf4}"

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
echo "Downloading CMX ${VERSION} (${OS}/${ARCH})"
DOWNLOAD_SUCCESS=0

curl_download() {
  if [ -t 2 ]; then
    curl --fail --show-error --location --progress-bar "$@"
  else
    curl --fail --silent --show-error --location "$@"
  fi
}

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
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

DOWNLOADED_BYTES="$(wc -c < "${TMP_DIR}/cmx" | tr -d '[:space:]')"
echo "Downloaded ${DOWNLOADED_BYTES} bytes."

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
if [ -w "$INSTALL_DIR" ]; then
  mv "${TMP_DIR}/cmx" "${INSTALL_DIR}/cmx"
else
  sudo mv "${TMP_DIR}/cmx" "${INSTALL_DIR}/cmx"
fi

echo "✓ CMX ${CMX_VERSION_STR#cmx version } ready — run: ${INSTALL_DIR}/cmx"

if [ "${CMX_SKIP_START:-0}" != "1" ]; then
  if ! "${INSTALL_DIR}/cmx" setup; then
    echo "Automatic setup could not finish. If sign-in is required, run cmx login; successful login completes setup automatically."
    exit 1
  fi
fi
