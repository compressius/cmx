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
trap 'rm -rf "$TMP_DIR"' EXIT
trap 'exit 1' HUP INT TERM

# Keep credentials out of downloader argv. Files are private from creation and
# removed by the temporary-directory trap on success, failure, or interruption.
if [ -n "${GITHUB_TOKEN:-}" ]; then
  case "$GITHUB_TOKEN" in
    *"$(printf '\r')"*|*'
'*)
      echo "Error: GITHUB_TOKEN must not contain line breaks" >&2
      exit 1
      ;;
  esac
  (
    umask 077
    printf 'Authorization: token %s\n' "$GITHUB_TOKEN" > "${TMP_DIR}/auth-header"
    printf 'header = Authorization: token %s\n' "$GITHUB_TOKEN" > "${TMP_DIR}/wgetrc"
  )
fi

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
    curl_download -H "@${TMP_DIR}/auth-header" -o "${TMP_DIR}/cmx" "$DOWNLOAD_URL" && DOWNLOAD_SUCCESS=1
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
      if curl_download -H "@${TMP_DIR}/auth-header" -o "${TMP_DIR}/cmx" "$DOWNLOAD_URL"; then
        DOWNLOAD_SUCCESS=1
      fi
    else
      if curl_download -o "${TMP_DIR}/cmx" "$DOWNLOAD_URL"; then
        DOWNLOAD_SUCCESS=1
      fi
    fi
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      if WGETRC="${TMP_DIR}/wgetrc" wget -q -O "${TMP_DIR}/cmx" "$DOWNLOAD_URL"; then
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
    curl -sSfL -H "@${TMP_DIR}/auth-header" -o "${TMP_DIR}/SHA256SUMS" "$CHECKSUM_URL" && CHECKSUM_SUCCESS=1
  else
    curl -sSfL -o "${TMP_DIR}/SHA256SUMS" "$CHECKSUM_URL" && CHECKSUM_SUCCESS=1
  fi
elif command -v wget >/dev/null 2>&1; then
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    WGETRC="${TMP_DIR}/wgetrc" wget -q -O "${TMP_DIR}/SHA256SUMS" "$CHECKSUM_URL" && CHECKSUM_SUCCESS=1
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
elif command -v shasum >/dev/null 2>&1; then
  expected="$(grep "  cmx-${OS}-${ARCH}$" "${TMP_DIR}/SHA256SUMS" | awk '{print $1}')"
  actual="$(shasum -a 256 "${TMP_DIR}/cmx" | awk '{print $1}')"
else
  echo "Error: sha256sum or shasum is required to verify the release"
  exit 1
fi
if [ -z "$expected" ]; then
  echo "Error: Release checksum is missing for cmx-${OS}-${ARCH}"
  exit 1
fi
if [ "$expected" != "$actual" ]; then
  echo "Error: Checksum mismatch. Nothing was installed."
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

configure_shell_path() {
  if [ "${CMX_NO_MODIFY_PATH:-0}" = "1" ]; then
    return 0
  fi

  case ":$PATH:" in
    *:"$INSTALL_DIR":*)
      return 0
      ;;
  esac

  if [ -z "$HOME" ]; then
    return 0
  fi

  case "$INSTALL_DIR" in
    "$HOME"/*)
      dir_expr="\$HOME/${INSTALL_DIR#$HOME/}"
      dir_display="~/${INSTALL_DIR#$HOME/}"
      ;;
    *)
      dir_expr="$INSTALL_DIR"
      dir_display="$INSTALL_DIR"
      ;;
  esac

  user_shell="$(basename "${SHELL:-bash}")"
  targets=""

  if [ -f "$HOME/.bashrc" ]; then
    targets="$targets $HOME/.bashrc"
  fi
  if [ -f "$HOME/.zshrc" ]; then
    targets="$targets $HOME/.zshrc"
  fi
  if [ -f "$HOME/.profile" ]; then
    targets="$targets $HOME/.profile"
  fi

  if [ -z "$targets" ]; then
    if [ "$user_shell" = "zsh" ]; then
      targets="$HOME/.zshrc"
    elif [ -f "$HOME/.bash_profile" ]; then
      targets="$HOME/.bash_profile"
    elif [ -f "$HOME/.profile" ]; then
      targets="$HOME/.profile"
    else
      targets="$HOME/.bashrc"
    fi
  fi

  configured_any=0
  for target_file in $targets; do
    if [ -f "$target_file" ] && (grep -F -q "$INSTALL_DIR" "$target_file" 2>/dev/null || \
       grep -F -q "$dir_expr" "$target_file" 2>/dev/null || \
       grep -F -q "Added by CMX" "$target_file" 2>/dev/null); then
      continue
    fi

    mkdir -p "$(dirname "$target_file")"
    {
      printf '\n# Added by CMX\n'
      printf 'if [ -d "%s" ] ; then\n' "$dir_expr"
      printf '    PATH="%s:$PATH"\n' "$dir_expr"
      printf 'fi\n'
    } >> "$target_file"

    case "$target_file" in
      "$HOME"/*) target_display="~/${target_file#$HOME/}" ;;
      *) target_display="$target_file" ;;
    esac
    echo "✓ Added ${dir_display} to PATH in ${target_display}"
    configured_any=1
  done

  if [ "$user_shell" = "fish" ] || [ -d "$HOME/.config/fish" ]; then
    fish_config="$HOME/.config/fish/config.fish"
    fish_has_entry=0
    if [ -f "$fish_config" ] && (grep -F -q "$INSTALL_DIR" "$fish_config" 2>/dev/null || grep -F -q "$dir_expr" "$fish_config" 2>/dev/null || grep -F -q "Added by CMX" "$fish_config" 2>/dev/null); then
      fish_has_entry=1
    fi
    if [ "$fish_has_entry" -eq 0 ]; then
      mkdir -p "$HOME/.config/fish"
      {
        printf '\n# Added by CMX\n'
        printf 'if test -d "%s"\n' "$dir_expr"
        printf '    set -gx PATH "%s" $PATH\n' "$dir_expr"
        printf 'end\n'
      } >> "$fish_config"
      echo "✓ Added ${dir_display} to PATH in ~/.config/fish/config.fish"
      configured_any=1
    fi
  fi

  export PATH="${INSTALL_DIR}:${PATH}"

  if [ "$configured_any" -eq 1 ]; then
    echo "  Run 'source ~/.bashrc' (or restart your terminal) to use 'cmx' from anywhere."
    echo ""
  else
    echo "Notice: ${dir_display} is configured in your shell profile, but not yet loaded in this session."
    echo "  Run 'export PATH=\"${INSTALL_DIR}:\$PATH\"' or restart your terminal."
    echo ""
  fi
}

configure_shell_path


if [ "${CMX_SKIP_START:-0}" != "1" ]; then
  setup_flag="--ask-connect-ready"
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    setup_flag="--connect-ready"
  fi
  if ! "${INSTALL_DIR}/cmx" setup $setup_flag; then
    echo "Automatic setup could not finish. Run cmx setup in an interactive terminal to retry."
    exit 1
  fi
  # Install systemd user autostart service if systemd is available
  if [ "$(uname -s)" = "Linux" ]; then
    "${INSTALL_DIR}/cmx" service install 2>/dev/null || true
    systemd_user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    if [ -f "${systemd_user_dir}/cmx.service" ]; then
      mkdir -p "${systemd_user_dir}/default.target.wants"
      ln -sf "${systemd_user_dir}/cmx.service" "${systemd_user_dir}/default.target.wants/cmx.service"
      if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user start cmx 2>/dev/null || true
      fi
    fi
  fi
  if ! "${INSTALL_DIR}/cmx" harness verify; then
    "${INSTALL_DIR}/cmx" stop || true
    echo "Automatic configuration was rolled back because the CMX gateway was unavailable."
    exit 1
  fi
fi
