# Claude Desktop — Flatpak

An **unofficial** Flatpak repackage of [Claude Desktop for Linux](https://code.claude.com/docs/en/desktop-linux)
(currently in beta). Anthropic ships the app only as a `.deb`; this manifest
extracts that prebuilt, signed Electron app and runs it inside a Flatpak
sandbox via [zypak](https://github.com/refi64/zypak). The app binary is **not**
modified or rebuilt.

Supports `x86_64` and `aarch64` (the two architectures Anthropic publishes).

## Build & install

```sh
./build.sh
flatpak run com.anthropic.ClaudeDesktop
```

`build.sh` adds the Flathub remote (user), installs the runtime + Electron
BaseApp, and builds with `flatpak-builder`. If `flatpak-builder` isn't on your
`PATH` it falls back to `nix run nixpkgs#flatpak-builder`.

To build manually:

```sh
flatpak-builder --user --install --force-clean build-dir com.anthropic.ClaudeDesktop.yaml
```

### NixOS

`flatpak` itself must be enabled at the system level — a `nix shell` alone
isn't enough (it needs the setuid `bwrap` / portals wired up by the module):

```nix
# configuration.nix
services.flatpak.enable = true;
xdg.portal.enable = true;
# a portal backend for your desktop, e.g.:
xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
```

`flatpak-builder` can come from `nix` on demand (the build script handles this),
or add `pkgs.flatpak-builder` to your environment.

## Updating

Anthropic pushes new builds to their apt repo. To bump:

```sh
./update-version.sh   # rewrites version + sha256 for both arches
git diff              # review
./build.sh
```

The pinned version and per-arch `sha256` sums live in
`com.anthropic.ClaudeDesktop.yaml`.

## What works / what doesn't

- **Chat, Claude Code** (integrated terminal, editor, diff review): work.
- **Credentials, notifications, tray icon**: wired up via the Secret Service,
  notification, and StatusNotifier D-Bus names in `finish-args`.
- **Cowork**: **not functional out of the box.** Cowork runs a `qemu` microVM
  (the app bundles `smol-bin.*.img`, `virtiofsd`, and `cowork-linux-helper`,
  but *not* `qemu`, which the `.deb` only *Recommends* from the host). The
  sandbox is already allowed `--device=kvm`; making Cowork work would
  additionally require bundling `qemu-system` + `ovmf` as extra modules.
- **Sandbox caveat for Claude Code:** the integrated terminal runs *inside* the
  Flatpak sandbox, so it sees the runtime's tools — not compilers/interpreters
  installed on your host (especially relevant on NixOS). `--filesystem=home`
  lets it read/write your project files and shares `~/.claude` with the CLI, but
  host toolchains aren't on `PATH` inside the sandbox. If you rely on
  host-installed dev tools, the native `.deb` or the CLI may suit you better.

## Permissions

See `finish-args` in the manifest. Notably `--filesystem=home` is broad; narrow
it to specific project directories (e.g. `--filesystem=~/code`) if you want
tighter isolation.

## How it works

1. `flatpak-builder` downloads the official per-arch `.deb` (checksum-pinned).
2. The `.deb` (an `ar` archive) is unpacked with `ar` + `tar` from the SDK.
3. `usr/lib/claude-desktop` is copied to `/app/lib/claude-desktop`; the SUID
   `chrome-sandbox` is dropped (zypak replaces it).
4. A wrapper (`claude-desktop.sh`) launches the Electron binary via
   `zypak-wrapper`.
5. Upstream's `.desktop` (kept for the `claude://` handler + actions) and icons
   are renamed to the app-id and exported.

## Disclaimer

Not affiliated with or endorsed by Anthropic. "Claude" and related marks belong
to Anthropic. This repository only contains packaging metadata — no Anthropic
code or binaries are redistributed here; they are fetched from Anthropic's
servers at build time.
