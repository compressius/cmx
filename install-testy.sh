#!/bin/sh
set -e

# CMX Testy Install Script (linux/amd64 only)
# Usage: curl -sSfL https://compressi.us/install-testy.sh | sh
#
# Requires: gh auth login (draft releases need authentication)
# Or set GITHUB_TOKEN in the environment.

REPO="${CMX_RELEASE_REPO:-compressius/cmx}"
VERSION="${CMX_VERSION:-v0.2.38-testy.20260919223127.5bd65e6d550b}"

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

# Testy builds are linux/amd64 only.
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  *)
    echo "Error: Testy builds are only available for x86_64. Got: $ARCH"
    exit 1
    ;;
esac

case "$OS" in
  linux) ;;
  *)
    echo "Error: Testy builds are only available for Linux. Got: $OS"
    exit 1
    ;;
esac

echo "Installing CMX testy build for ${OS}/${ARCH}..."

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/cmx-${OS}-${ARCH}"

# Create temp directory
TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'cmx')"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

echo "Downloading CMX ${VERSION} (${OS}/${ARCH})"
DOWNLOAD_SUCCESS=0

# Testy builds are draft releases — they require authentication.
# Try gh CLI first (preferred), then curl with GITHUB_TOKEN.
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  if gh release download "$VERSION" -p "cmx-${OS}-${ARCH}" -O "${TMP_DIR}/cmx" --repo "$REPO" >/dev/null 2>&1; then
    DOWNLOAD_SUCCESS=1
  fi
fi

if [ "$DOWNLOAD_SUCCESS" -ne 1 ] && [ -n "${GITHUB_TOKEN:-}" ]; then
  if command -v curl >/dev/null 2>&1; then
    if curl --fail --silent --show-error --location \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/octet-stream" \
      -o "${TMP_DIR}/cmx" "$DOWNLOAD_URL"; then
      DOWNLOAD_SUCCESS=1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if wget -q \
      --header="Authorization: token ${GITHUB_TOKEN}" \
      --header="Accept: application/octet-stream" \
      -O "${TMP_DIR}/cmx" "$DOWNLOAD_URL"; then
      DOWNLOAD_SUCCESS=1
    fi
  fi
fi

if [ "$DOWNLOAD_SUCCESS" -ne 1 ]; then
  echo "Error: Download failed. Testy builds are draft releases and require authentication."
  echo "  Option 1: Install gh CLI and run 'gh auth login'"
  echo "  Option 2: Set GITHUB_TOKEN environment variable"
  exit 1
fi

DOWNLOADED_BYTES="$(wc -c < "${TMP_DIR}/cmx" | tr -d '[:space:]')"
echo "Downloaded ${DOWNLOADED_BYTES} bytes."

# Verify the downloaded artifact against the release checksum.
CHECKSUM_SUCCESS=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  if gh release download "$VERSION" -p "SHA256SUMS" -O "${TMP_DIR}/SHA256SUMS" --repo "$REPO" >/dev/null 2>&1; then
    CHECKSUM_SUCCESS=1
  fi
fi
if [ "$CHECKSUM_SUCCESS" -ne 1 ] && [ -n "${GITHUB_TOKEN:-}" ] && command -v curl >/dev/null 2>&1; then
  CHECKSUM_URL="https://github.com/${REPO}/releases/download/${VERSION}/SHA256SUMS"
  if curl -sSfL -H "Authorization: token ${GITHUB_TOKEN}" -o "${TMP_DIR}/SHA256SUMS" "$CHECKSUM_URL"; then
    CHECKSUM_SUCCESS=1
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
