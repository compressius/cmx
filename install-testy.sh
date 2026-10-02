#!/bin/sh
set -e

# CMX Testy Install Script (linux/amd64 only)
# Usage: curl -sSfL https://compressi.us/install-testy.sh | sh

REPO="${CMX_RELEASE_REPO:-compressius/cmx}"
VERSION="${CMX_VERSION:-v0.2.44-testy.20261002212622.3d6eb1c5aba6}"

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

echo "Downloading CMX ${VERSION} (${OS}/${ARCH})"
DOWNLOAD_SUCCESS=0

# Interactive terminals get curl's transfer bar; piped output stays plain.
curl_download() {
  if [ -t 2 ]; then
    curl --fail --show-error --location --progress-bar "$@"
  else
    curl --fail --silent --show-error --location "$@"
  fi
}

if command -v curl >/dev/null 2>&1; then
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl_download -H "@${TMP_DIR}/auth-header" -o "${TMP_DIR}/cmx" "$DOWNLOAD_URL" && DOWNLOAD_SUCCESS=1
  else
    curl_download -o "${TMP_DIR}/cmx" "$DOWNLOAD_URL" && DOWNLOAD_SUCCESS=1
  fi
elif command -v wget >/dev/null 2>&1; then
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    WGETRC="${TMP_DIR}/wgetrc" wget -q -O "${TMP_DIR}/cmx" "$DOWNLOAD_URL" && DOWNLOAD_SUCCESS=1
  else
    wget -q -O "${TMP_DIR}/cmx" "$DOWNLOAD_URL" && DOWNLOAD_SUCCESS=1
  fi
fi

if [ "$DOWNLOAD_SUCCESS" -ne 1 ] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  if gh release download "$VERSION" -p "cmx-${OS}-${ARCH}" -O "${TMP_DIR}/cmx" --repo "$REPO" >/dev/null 2>&1; then
    DOWNLOAD_SUCCESS=1
  fi
fi

if [ "$DOWNLOAD_SUCCESS" -ne 1 ]; then
  echo "Error: Download failed from ${DOWNLOAD_URL}"
  exit 1
fi

DOWNLOADED_BYTES="$(wc -c < "${TMP_DIR}/cmx" | tr -d '[:space:]')"
echo "Downloaded ${DOWNLOADED_BYTES} bytes."

# Verify the downloaded artifact against the release checksum.
CHECKSUM_SUCCESS=0
CHECKSUM_URL="https://github.com/${REPO}/releases/download/${VERSION}/SHA256SUMS"
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
    wget -q -O "${TMP_DIR}/SHA256SUMS" "$CHECKSUM_URL" && CHECKSUM_SUCCESS=1
  fi
fi

if [ "$CHECKSUM_SUCCESS" -ne 1 ] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  if gh release download "$VERSION" -p "SHA256SUMS" -O "${TMP_DIR}/SHA256SUMS" --repo "$REPO" >/dev/null 2>&1; then
    CHECKSUM_SUCCESS=1
  fi
fi

if [ "$CHECKSUM_SUCCESS" -ne 1 ]; then
  echo "Error: Release checksum download failed from ${CHECKSUM_URL}"
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
if [ -w "$INSTALL_DIR" ]; then
  mv "${TMP_DIR}/cmx" "${INSTALL_DIR}/cmx"
else
  sudo mv "${TMP_DIR}/cmx" "${INSTALL_DIR}/cmx"
fi

echo "✓ CMX ${CMX_VERSION_STR#cmx version } ready — run: ${INSTALL_DIR}/cmx"

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
    echo "Automatic setup could not finish. If sign-in is required, run cmx login; successful login completes setup automatically."
    exit 1
  fi
  # Ensure update.channel is set to testy
  config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/cmx"
  if [ -f "${config_dir}/config.json" ]; then
    if command -v jq >/dev/null 2>&1; then
      tmp_cfg="$(mktemp)"
      jq '.update.channel = "testy"' "${config_dir}/config.json" > "$tmp_cfg" 2>/dev/null && mv "$tmp_cfg" "${config_dir}/config.json" || rm -f "$tmp_cfg"
    elif command -v sed >/dev/null 2>&1; then
      sed -i 's/"channel":[[:space:]]*"[^"]*"/"channel": "testy"/g' "${config_dir}/config.json" 2>/dev/null || true
    fi
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
