#!/usr/bin/env bash

# install.sh - Wallpaper Picker installer for Linux Mint

set -euo pipefail

APP_NAME="wallpaper-picker"
APP_DISPLAY_NAME="Wallpaper Picker"
APP_COMMENT="Browse and set your desktop wallpaper"
APP_VERSION="1.0.0"
APP_SCRIPT="wallpaper-picker.pl"
APP_ICON_SRC="wallpaper-picker.svg"

INSTALL_DIR="${HOME}/.local/bin"
DESKTOP_DIR="${HOME}/.local/share/applications"
ICON_DIR="${HOME}/.local/share/perl-wallpaper-picker/application-icon"
AUTOSTART_DIR="${HOME}/.config/autostart"

SHELL_RC=""

info()    { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
success() { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }
warn()    { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
die()     { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

require_file() {
    [[ -f "$1" ]] || die "Required file not found: $1"
}

detect_shell_rc() {
    local shell_name
    shell_name="$(basename "${SHELL:-/bin/bash}")"
    case "$shell_name" in
        bash) SHELL_RC="${HOME}/.bashrc" ;;
        zsh)  SHELL_RC="${HOME}/.zshrc"  ;;
        fish) SHELL_RC="${HOME}/.config/fish/config.fish" ;;
        *)    SHELL_RC="${HOME}/.profile" ;;
    esac
}

install_apt_deps() {
    info "Installing system dependencies via apt…"

    local apt_packages=(
        perl
        cpanminus
        libgtk3-perl
        libglib-perl
        libdigest-sha-perl
        libscalar-list-utils-perl
    )

    sudo apt-get update -qq
    sudo apt-get install -y "${apt_packages[@]}"
    success "System packages installed."
}

install_cpan_deps() {
    info "Installing CPAN dependencies…"

    local cpan_modules=(
        Moo
        Scalar::Util
    )

    for mod in "${cpan_modules[@]}"; do
        if perl -M"$mod" -e1 2>/dev/null; then
            success "CPAN module already available: $mod"
        else
            info "Installing $mod via cpanm…"
            cpanm --notest --quiet "$mod" \
                || die "Failed to install CPAN module: $mod"
            success "Installed: $mod"
        fi
    done
}

install_icon() {
    info "Installing icon to ${ICON_DIR}…"

    require_file "${APP_ICON_SRC}"

    mkdir -p "${ICON_DIR}"
    cp "${APP_ICON_SRC}" "${ICON_DIR}/${APP_ICON_SRC}"
    chmod 644 "${ICON_DIR}/${APP_ICON_SRC}"

    success "Icon installed to ${ICON_DIR}/${APP_ICON_SRC}."
}

install_script() {
    info "Installing ${APP_SCRIPT} to ${INSTALL_DIR}…"

    require_file "${APP_SCRIPT}"

    mkdir -p "${INSTALL_DIR}"
    cp "${APP_SCRIPT}" "${INSTALL_DIR}/${APP_NAME}"
    chmod 755 "${INSTALL_DIR}/${APP_NAME}"

    success "Script installed to ${INSTALL_DIR}/${APP_NAME}."
}

add_to_path() {
    detect_shell_rc

    info "Checking PATH for ${INSTALL_DIR}…"

    local path_snippet

    if [[ "$(basename "${SHELL:-bash}")" == "fish" ]]; then
        path_snippet="fish_add_path \"\$HOME/.local/bin\""
    else
        path_snippet='export PATH="${HOME}/.local/bin:${PATH}"'
    fi

    if echo "${PATH}" | tr ':' '\n' | grep -qxF "${INSTALL_DIR}"; then
        success "${INSTALL_DIR} is already in PATH."
        return
    fi

    if grep -qF '.local/bin' "${SHELL_RC}" 2>/dev/null; then
        success "${INSTALL_DIR} already referenced in ${SHELL_RC}."
        return
    fi

    {
        printf '\n# Added by %s installer\n' "${APP_DISPLAY_NAME}"
        printf '%s\n' "${path_snippet}"
    } >> "${SHELL_RC}"

    success "Added ${INSTALL_DIR} to PATH in ${SHELL_RC}."
    warn "Run 'source ${SHELL_RC}' or open a new terminal for PATH to take effect."
}

create_desktop_file() {
    info "Creating .desktop entry…"

    mkdir -p "${DESKTOP_DIR}"

    local desktop_file="${DESKTOP_DIR}/${APP_NAME}.desktop"

    cat > "${desktop_file}" <<EOF
[Desktop Entry]
Version=${APP_VERSION}
Type=Application
Name=${APP_DISPLAY_NAME}
Comment=${APP_COMMENT}
Exec=${INSTALL_DIR}/${APP_NAME}
Icon=${ICON_DIR}/${APP_ICON_SRC}
Terminal=false
Categories=GTK;Settings;DesktopSettings;
Keywords=wallpaper;background;desktop;image;
StartupNotify=false
StartupWMClass=wallpaper-picker
EOF

    chmod 644 "${desktop_file}"
    success "Desktop file created: ${desktop_file}"
}

register_application() {
    info "Updating XDG application database…"

    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "${DESKTOP_DIR}" 2>/dev/null \
            && success "Desktop database updated." \
            || warn "update-desktop-database reported a non-fatal warning."
    else
        warn "update-desktop-database not found; skipping (app should still appear in menu)."
    fi
}

verify_install() {
    info "Verifying installation…"

    local ok=1

    [[ -x "${INSTALL_DIR}/${APP_NAME}" ]] \
        && success "Executable present: ${INSTALL_DIR}/${APP_NAME}" \
        || { warn "Executable missing!"; ok=0; }

    [[ -f "${ICON_DIR}/${APP_ICON_SRC}" ]] \
        && success "Icon present: ${ICON_DIR}/${APP_ICON_SRC}" \
        || { warn "Icon missing!"; ok=0; }

    [[ -f "${DESKTOP_DIR}/${APP_NAME}.desktop" ]] \
        && success "Desktop file present: ${DESKTOP_DIR}/${APP_NAME}.desktop" \
        || { warn "Desktop file missing!"; ok=0; }

    perl -e 'use Moo; use Gtk3; use Glib; use Digest::SHA; use File::Path; use Scalar::Util;' 2>/dev/null \
        && success "All required Perl modules load cleanly." \
        || { warn "One or more Perl modules failed to load — check CPAN output above."; ok=0; }

    if [[ $ok -eq 1 ]]; then
        printf '\n\033[1;32m✓ Installation complete.\033[0m\n'
        printf '  Run with:  %s\n' "${APP_NAME}"
        printf '  Or launch from the application menu: "%s"\n\n' "${APP_DISPLAY_NAME}"
    else
        printf '\n\033[1;33m⚠ Installation finished with warnings — review output above.\033[0m\n\n'
    fi
}

main() {
    printf '\n\033[1;37m=== %s Installer v%s ===\033[0m\n\n' \
        "${APP_DISPLAY_NAME}" "${APP_VERSION}"

    cd "$(dirname "$(realpath "$0")")"

    install_apt_deps
    install_cpan_deps
    install_icon
    install_script
    add_to_path
    create_desktop_file
    register_application
    verify_install
}

main "$@"
