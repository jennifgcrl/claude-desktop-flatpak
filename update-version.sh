#!/usr/bin/env bash
# Bump the manifest to the latest claude-desktop version by reading Anthropic's
# apt Packages index. Rewrites the version in the URLs, the two sha256 sums,
# and the metainfo <release>. Review the diff before committing.
set -euo pipefail
cd "$(dirname "$0")"

BASE="https://downloads.claude.ai/claude-desktop/apt/stable"
MANIFEST="com.anthropic.ClaudeDesktop.yaml"
METAINFO="com.anthropic.ClaudeDesktop.metainfo.xml"

# Latest version + sha256 for one architecture, from the Packages index.
latest() { # $1 = amd64|arm64
  curl -fsSL "$BASE/dists/stable/main/binary-$1/Packages" | awk '
    BEGIN { RS = "" }
    /Package: claude-desktop/ {
      v = ""; sha = "";
      n = split($0, L, "\n");
      for (i = 1; i <= n; i++) {
        if (L[i] ~ /^Version:/) { split(L[i], a, " "); v = a[2] }
        if (L[i] ~ /^SHA256:/)  { split(L[i], a, " "); sha = a[2] }
      }
      print v, sha
    }' | sort -V | tail -n1
}

read -r VER AMD_SHA < <(latest amd64)
read -r VER_ARM ARM_SHA < <(latest arm64)
[ "$VER" = "$VER_ARM" ] || { echo "arch versions differ ($VER vs $VER_ARM)"; exit 1; }
echo "Latest: $VER"
echo "  amd64 $AMD_SHA"
echo "  arm64 $ARM_SHA"

sed -i -E \
  -e "s#claude-desktop_[0-9.]+_amd64\.deb#claude-desktop_${VER}_amd64.deb#" \
  -e "s#claude-desktop_[0-9.]+_arm64\.deb#claude-desktop_${VER}_arm64.deb#" \
  "$MANIFEST"

# Replace the sha256 line that follows each per-arch .deb url.
awk -v amd="$AMD_SHA" -v arm="$ARM_SHA" '
  /_amd64\.deb$/ { print; getline; sub(/sha256: .*/, "sha256: " amd); print; next }
  /_arm64\.deb$/ { print; getline; sub(/sha256: .*/, "sha256: " arm); print; next }
  { print }
' "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"

sed -i -E \
  "s#<release version=\"[0-9.]+\" date=\"[0-9-]+\"#<release version=\"${VER}\" date=\"$(date +%F)\"#" \
  "$METAINFO"

echo "Updated $MANIFEST and $METAINFO to $VER. Review 'git diff', then ./build.sh."
