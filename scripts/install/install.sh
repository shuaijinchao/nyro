#!/usr/bin/env bash
# Nyro AI Gateway Install Script (Linux + macOS)
# Usage: curl -fsSL https://raw.githubusercontent.com/shuaijinchao/nyro/master/scripts/install/install.sh | bash
#
# Environment variables:
#   VERSION   - Install specific version (e.g. "1.0.0"), default: latest
#   DRY_RUN   - Set to "1" to print commands without executing

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPO="shuaijinchao/nyro"
APP_NAME="Nyro"
GITHUB_API="https://api.github.com/repos/${REPO}/releases"

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
die()     { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

run() {
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
    else
        "$@"
    fi
}

show_help() {
    cat << EOF
${APP_NAME} AI Gateway Install Script

Usage:
    curl -fsSL https://raw.githubusercontent.com/${REPO}/main/scripts/install/install.sh | bash

    # Install specific version
    curl -fsSL https://raw.githubusercontent.com/${REPO}/main/scripts/install/install.sh | VERSION=1.0.0 bash

Environment Variables:
    VERSION     Install specific version (default: latest)
    DRY_RUN     Set to "1" to preview commands without executing

Supported Platforms:
    - macOS arm64 (Apple Silicon): .dmg
    - macOS x86_64 (Intel):        .dmg
    - Linux x86_64:                .AppImage
    - Linux aarch64:               .AppImage

EOF
    exit 0
}

detect_platform() {
    OS="$(uname -s)"
    ARCH="$(uname -m)"

    case "$OS" in
        Linux)  PLATFORM="linux" ;;
        Darwin) PLATFORM="macos" ;;
        *)      die "Unsupported OS: $OS. Use install.ps1 for Windows." ;;
    esac

    case "$ARCH" in
        x86_64|amd64)   ARCH_LABEL="x86_64"; DMG_ARCH="x64"; DEB_ARCH="amd64" ;;
        aarch64|arm64)  ARCH_LABEL="aarch64"; DMG_ARCH="aarch64"; DEB_ARCH="arm64" ;;
        *)              die "Unsupported architecture: $ARCH" ;;
    esac

    info "Detected: $PLATFORM ($ARCH_LABEL)"
}

detect_linux_pkg_manager() {
    [[ "$PLATFORM" != "linux" ]] && return
    PKG_EXT="AppImage"
    info "Package format: AppImage"
}

get_version() {
    if [[ -n "${VERSION:-}" ]]; then
        RELEASE_VERSION="$VERSION"
        info "Using specified version: v$RELEASE_VERSION"
        return
    fi

    info "Fetching latest version..."

    local response
    if response=$(curl -fsSL -H "User-Agent: Nyro-Installer" "${GITHUB_API}/latest" 2>/dev/null); then
        RELEASE_VERSION=$(echo "$response" | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
        if [[ -n "$RELEASE_VERSION" ]]; then
            info "Latest version: v$RELEASE_VERSION"
            return
        fi
    fi

    local redirect_url
    redirect_url=$(curl -fsSI "https://github.com/${REPO}/releases/latest" 2>/dev/null \
        | grep -i "^location:" | tr -d '\r' | awk '{print $2}')

    if [[ -n "$redirect_url" ]]; then
        RELEASE_VERSION=$(echo "$redirect_url" | sed -E 's|.*/tag/v||')
    fi

    if [[ -z "${RELEASE_VERSION:-}" ]]; then
        die "Failed to fetch latest version. Try: VERSION=1.0.0 bash install.sh"
    fi

    info "Latest version: v$RELEASE_VERSION"
}

build_download_url() {
    local base_url="https://github.com/${REPO}/releases/download/v${RELEASE_VERSION}"

    case "$PLATFORM" in
        macos)
            DOWNLOAD_URL="${base_url}/Nyro_${RELEASE_VERSION}_${DMG_ARCH}.dmg"
            FILENAME="Nyro_${RELEASE_VERSION}_${DMG_ARCH}.dmg"
            ;;
        linux)
            DOWNLOAD_URL="${base_url}/Nyro_${RELEASE_VERSION}_${DEB_ARCH}.AppImage"
            FILENAME="Nyro_${RELEASE_VERSION}_${DEB_ARCH}.AppImage"
            ;;
    esac

    info "Download URL: $DOWNLOAD_URL"
}

download_installer() {
    TEMP_DIR=$(mktemp -d)
    DOWNLOAD_PATH="${TEMP_DIR}/${FILENAME}"

    info "Downloading ${APP_NAME} v${RELEASE_VERSION}..."
    run curl -fSL --progress-bar -o "$DOWNLOAD_PATH" "$DOWNLOAD_URL"

    if [[ "${DRY_RUN:-0}" != "1" ]] && [[ ! -f "$DOWNLOAD_PATH" ]]; then
        die "Download failed. Check your network or try a different version."
    fi

    success "Downloaded to $DOWNLOAD_PATH"
}

install_linux() {
    info "Installing ${APP_NAME}..."

    local install_dir="${HOME}/.local/bin"
    run mkdir -p "$install_dir"
    run chmod +x "$DOWNLOAD_PATH"
    run cp "$DOWNLOAD_PATH" "${install_dir}/nyro"

    if [[ ":$PATH:" != *":${install_dir}:"* ]]; then
        warn "Add ${install_dir} to your PATH:"

        local shell_name rc_file export_line
        shell_name="$(basename "${SHELL:-/bin/bash}")"
        case "$shell_name" in
            zsh)  rc_file="$HOME/.zshrc" ;;
            fish) rc_file="$HOME/.config/fish/config.fish" ;;
            *)    rc_file="$HOME/.bashrc" ;;
        esac

        export_line="export PATH=\"${install_dir}:\$PATH\""
        [[ "$shell_name" == "fish" ]] && export_line="fish_add_path ${install_dir}"

        if [[ -f "$rc_file" ]] && grep -qF "$install_dir" "$rc_file" 2>/dev/null; then
            info "PATH entry already in $rc_file"
        else
            run echo "$export_line" >> "$rc_file"
            info "Added ${install_dir} to PATH in $rc_file"
            warn "Run: source $rc_file  (or restart terminal)"
        fi
    fi

    success "${APP_NAME} installed successfully!"
}

install_macos() {
    info "Installing ${APP_NAME}..."

    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} hdiutil attach $DOWNLOAD_PATH -nobrowse -noautoopen"
        echo -e "${YELLOW}[DRY-RUN]${NC} cp -R <mount>/${APP_NAME}.app /Applications/"
        echo -e "${YELLOW}[DRY-RUN]${NC} hdiutil detach <mount>"
        echo -e "${YELLOW}[DRY-RUN]${NC} sudo xattr -rd com.apple.quarantine /Applications/${APP_NAME}.app"
        return
    fi

    local mount_output mount_point
    mount_output=$(hdiutil attach "$DOWNLOAD_PATH" -nobrowse -noautoopen 2>&1)
    mount_point=$(echo "$mount_output" | grep -o '/Volumes/.*' | head -n1)

    if [[ -z "$mount_point" ]]; then
        die "Failed to mount DMG. Output: $mount_output"
    fi

    if [[ -d "/Applications/${APP_NAME}.app" ]]; then
        info "Removing existing installation..."
        rm -rf "/Applications/${APP_NAME}.app"
    fi
    cp -R "${mount_point}/${APP_NAME}.app" /Applications/

    hdiutil detach "$mount_point" -quiet 2>/dev/null || true

    info "Removing quarantine attribute..."
    sudo xattr -rd com.apple.quarantine "/Applications/${APP_NAME}.app" 2>/dev/null || true

    success "${APP_NAME} installed to /Applications!"
}

cleanup() {
    if [[ -n "${TEMP_DIR:-}" ]] && [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

main() {
    for arg in "$@"; do
        case "$arg" in
            --help|-h)    show_help ;;
            --version|-v) echo "install.sh v1.0.0"; exit 0 ;;
        esac
    done

    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    ${APP_NAME} AI Gateway Installer${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    trap cleanup EXIT

    detect_platform
    detect_linux_pkg_manager
    get_version
    build_download_url
    download_installer

    case "$PLATFORM" in
        linux) install_linux ;;
        macos) install_macos ;;
    esac

    echo ""
    success "Installation complete!"
    echo ""
    info "Launch '${APP_NAME}' from your application menu."
    echo ""
}

main "$@"
