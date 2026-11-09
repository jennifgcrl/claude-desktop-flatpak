#!/usr/bin/env bash
# Bump the manifest to the latest claude-desktop version by reading Anthropic's
# apt Packages index. Rewrites the version in the URLs, the two sha256 sums,
# and the metainfo <release>. Also bumps the OVMF firmware to the version in
# Debian testing, since Debian's pool drops old versions. Review the diff
# before committing.
set -euo pipefail
cd "$(dirname "$0")"

BASE="https://downloads.claude.ai/claude-desktop/apt/stable"
MANIFEST="me.jezh.ClaudeDesktop.yaml"
METAINFO="me.jezh.ClaudeDesktop.metainfo.xml"

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

grep -qF "<release version=\"${VER}\"" "$METAINFO" || sed -i -E \
  "s#<release version=\"[0-9.]+\" date=\"[0-9-]+\"#<release version=\"${VER}\" date=\"$(date +%F)\"#" \
  "$METAINFO"

OVMF_VER=$(curl -fsSL "https://api.ftp-master.debian.org/madison?package=ovmf-generic&f=json&s=testing" \
  | jq -r '.[0]["ovmf-generic"].testing | keys | .[0]')
[ -n "$OVMF_VER" ] && [ "$OVMF_VER" != null ] || { echo "could not resolve ovmf-generic version"; exit 1; }
OVMF_DEB="ovmf-generic_${OVMF_VER#*:}_all.deb"
echo "OVMF: $OVMF_VER"

if ! grep -qF "/$OVMF_DEB" "$MANIFEST"; then
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSLo "$TMP/ovmf.deb" "https://deb.debian.org/debian/pool/main/e/edk2/$OVMF_DEB"
  OVMF_SHA256=$(sha256sum "$TMP/ovmf.deb" | cut -d' ' -f1)
  OVMF_SHA1=$(sha1sum "$TMP/ovmf.deb" | cut -d' ' -f1)
  echo "  sha256 $OVMF_SHA256"

  awk -v deb="$OVMF_DEB" -v sha="$OVMF_SHA256" -v sha1="$OVMF_SHA1" '
    /url: .*\/ovmf-generic_[^\/]*_all\.deb$/ {
      sub(/ovmf-generic_[^\/]*_all\.deb$/, deb); print
      getline; sub(/sha256: .*/, "sha256: " sha); print; next
    }
    /- https:\/\/snapshot\.debian\.org\// { sub(/https:.*/, "https://snapshot.debian.org/file/" sha1); print; next }
    { print }
  ' "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
fi

echo "Updated $MANIFEST and $METAINFO (claude-desktop $VER, OVMF $OVMF_VER). Review 'git diff', then ./build.sh."
