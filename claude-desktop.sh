#!/bin/sh
# Launch the bundled Electron binary through zypak so Chromium's sandbox works
# inside the Flatpak sandbox (no SUID chrome-sandbox). Extra args (and the
# claude:// URL passed via %U in the .desktop file) are forwarded through.
exec zypak-wrapper /app/lib/claude-desktop/claude-desktop "$@"
