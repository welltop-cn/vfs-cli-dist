#!/bin/sh
# vfs-cli installer.
#
#   curl -fsSL https://raw.githubusercontent.com/welltop-cn/vfs-cli-dist/main/install.sh | sh
#
# Downloads the right vfs-cli binary for your OS/arch from GitHub Releases and
# installs it onto your PATH. POSIX sh, no bashisms.
#
# The source repo (welltop-cn/vfs-cli) is private, so binaries and this script
# are published to a separate PUBLIC distribution repo. All anonymous downloads
# target the dist repo; SRC_REPO is only used for the build-from-source hint.
#
# Environment overrides:
#   VFS_CLI_VERSION   Tag to install (default: latest release). e.g. v1.2.3
#   VFS_CLI_INSTALL_DIR  Target dir (default: /usr/local/bin, or ~/.local/bin
#                        if that is not writable).
set -eu

REPO="welltop-cn/vfs-cli-dist"     # public repo hosting the release assets
SRC_REPO="welltop-cn/vfs-cli"      # private source repo (build-from-source hint)
BINARY="vfs-cli"

err() { printf 'install: %s\n' "$1" >&2; exit 1; }
info() { printf '%s\n' "$1" >&2; }

# --- detect platform ---------------------------------------------------------
os=$(uname -s)
arch=$(uname -m)

case "$os" in
  Darwin) os="darwin" ;;
  Linux)  os="linux" ;;
  *) err "unsupported OS: $os (supported: macOS, Linux)" ;;
esac

case "$arch" in
  arm64|aarch64) arch="arm64" ;;
  x86_64|amd64)  arch="amd64" ;;
  *) err "unsupported architecture: $arch (supported: arm64, amd64)" ;;
esac

# We only publish a subset of os/arch combos; reject the rest with a clear msg.
target="${os}_${arch}"
case "$target" in
  darwin_arm64|darwin_amd64|linux_amd64) ;;
  *) err "no published binary for ${os}/${arch}; build from source: go install github.com/${SRC_REPO}/cmd/vfs-cli@latest" ;;
esac

# --- resolve version ---------------------------------------------------------
version="${VFS_CLI_VERSION:-}"
if [ -z "$version" ]; then
  info "Resolving latest release..."
  version=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep '"tag_name"' | head -1 | cut -d '"' -f 4)
  [ -n "$version" ] || err "could not determine latest version; set VFS_CLI_VERSION explicitly"
fi

# --- download ----------------------------------------------------------------
# Release asset name convention (matches the GitHub Actions workflow):
#   vfs-cli_<version>_<os>_<arch>.tar.gz
asset="${BINARY}_${version}_${target}.tar.gz"
url="https://github.com/${REPO}/releases/download/${version}/${asset}"

tmp=$(mktemp -d 2>/dev/null || mktemp -d -t vfs-cli)
trap 'rm -rf "$tmp"' EXIT

info "Downloading ${BINARY} ${version} (${os}/${arch})..."
if ! curl -fsSL "$url" -o "$tmp/$asset"; then
  err "download failed: $url"
fi

tar -xzf "$tmp/$asset" -C "$tmp" || err "failed to extract $asset"
[ -f "$tmp/$BINARY" ] || err "archive did not contain a '$BINARY' binary"
chmod +x "$tmp/$BINARY"

# --- pick install dir --------------------------------------------------------
install_dir="${VFS_CLI_INSTALL_DIR:-}"
if [ -z "$install_dir" ]; then
  if [ -w /usr/local/bin ] 2>/dev/null; then
    install_dir="/usr/local/bin"
  else
    install_dir="$HOME/.local/bin"
  fi
fi
mkdir -p "$install_dir" 2>/dev/null || true

dest="$install_dir/$BINARY"
if mv "$tmp/$BINARY" "$dest" 2>/dev/null; then
  :
elif command -v sudo >/dev/null 2>&1; then
  info "Elevating with sudo to write $install_dir..."
  sudo mv "$tmp/$BINARY" "$dest" || err "failed to install to $dest"
else
  err "cannot write to $install_dir and sudo not available; set VFS_CLI_INSTALL_DIR to a writable dir"
fi

# --- verify + PATH hint ------------------------------------------------------
info ""
info "Installed: $dest"
"$dest" version >/dev/null 2>&1 && info "Verified: $("$dest" --version 2>/dev/null || echo "$version")"

case ":$PATH:" in
  *":$install_dir:"*) ;;
  *)
    info ""
    info "WARNING: $install_dir is not on your PATH."
    info "Add it, e.g.:  echo 'export PATH=\"$install_dir:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
    ;;
esac

# --- skills install hint -----------------------------------------------------
# Skills ship inside the binary. Installing them to disk lets an AI agent
# auto-trigger them at runtime. We only print guidance: we cannot know which
# project to target from a piped installer, and we never write to your home.
info ""
info "Next: enable skills for AI agents."
info "  cd into your VFS project, then run:  vfs-cli skills install"
info "  This unpacks the embedded skills into ./.claude/skills so an agent"
info "  picks them up automatically. Use --global to install to ~/.claude/skills."
