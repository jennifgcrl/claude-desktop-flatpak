#!/usr/bin/env bash
# Build and install the Claude Desktop Flatpak (user install).
#
# On NixOS, flatpak-builder may not be on PATH; this script falls back to
# `nix shell nixpkgs#flatpak-builder nixpkgs#appstream`. flatpak itself must be
# enabled at the system level (services.flatpak.enable = true) — see README.
set -euo pipefail
cd "$(dirname "$0")"

MANIFEST="me.jezh.ClaudeDesktop.yaml"
APP_ID="me.jezh.ClaudeDesktop"

# The runtime, SDK and Electron BaseApp come from Flathub. --install-deps-from
# reads their exact versions from the manifest, so they can never drift from it.
flatpak --user remote-add --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo

# Prefer a real flatpak-builder; otherwise borrow one from nixpkgs. It shells
# out to `appstreamcli` for the metainfo, so pull appstream in alongside it.
if command -v flatpak-builder >/dev/null 2>&1; then
  fb() { flatpak-builder "$@"; }
elif command -v nix >/dev/null 2>&1; then
  echo "flatpak-builder not found; using nix (flatpak-builder + appstream)"
  fb() { nix shell nixpkgs#flatpak-builder nixpkgs#appstream --command flatpak-builder "$@"; }
else
  echo "error: need flatpak-builder (install it, or install Nix)." >&2
  exit 1
fi

fb --user --install-deps-from=flathub --install --force-clean build-dir "$MANIFEST"

echo
echo "Installed. Launch with:  flatpak run $APP_ID"
