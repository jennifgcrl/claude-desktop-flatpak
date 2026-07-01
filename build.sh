#!/usr/bin/env bash
# Build and install the Claude Desktop Flatpak (user install).
#
# On NixOS, flatpak-builder may not be on PATH; this script falls back to
# `nix run nixpkgs#flatpak-builder`. flatpak itself must be enabled at the
# system level (services.flatpak.enable = true) — see README.
set -euo pipefail

MANIFEST="com.anthropic.ClaudeDesktop.yaml"
APP_ID="com.anthropic.ClaudeDesktop"
BUILD_DIR="build-dir"
cd "$(dirname "$0")"

# Ensure a user-level Flathub remote (runtimes come from here).
flatpak --user remote-add --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo

# Runtime, SDK and the Electron BaseApp the manifest depends on.
flatpak --user install -y flathub \
  org.freedesktop.Platform//24.08 \
  org.freedesktop.Sdk//24.08 \
  org.electronjs.Electron2.BaseApp//24.08

# Prefer a real flatpak-builder; otherwise borrow one from nixpkgs.
if command -v flatpak-builder >/dev/null 2>&1; then
  FB=(flatpak-builder)
elif command -v nix >/dev/null 2>&1; then
  echo "flatpak-builder not found; using nix run nixpkgs#flatpak-builder"
  FB=(nix run nixpkgs#flatpak-builder --)
else
  echo "error: need flatpak-builder (install it, or install Nix)." >&2
  exit 1
fi

"${FB[@]}" --user --install --force-clean --repo=repo "$BUILD_DIR" "$MANIFEST"

echo
echo "Installed. Launch with:  flatpak run $APP_ID"
