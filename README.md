# Claude Desktop — Flatpak

An **unofficial** Flatpak repackage of [Claude Desktop for Linux](https://code.claude.com/docs/en/desktop-linux)
(currently in beta). Anthropic ships the app only as a `.deb`; this manifest
extracts that prebuilt, signed Electron app and runs it inside a Flatpak
sandbox via [zypak](https://github.com/refi64/zypak). Claude's Electron binary
runs as-shipped — nothing is recompiled from source. (The only edit to the app
payload is a same-length path string inside `app.asar` so Cowork can find its
bundled firmware; see [How it works](#how-it-works).)

Supports `x86_64` and `aarch64` (the two architectures Anthropic publishes).

## Build & install

```sh
./build.sh
flatpak run me.jezh.ClaudeDesktop
```

`build.sh` adds the Flathub remote (user), then builds and installs with
`flatpak-builder` (`--install-deps-from=flathub` pulls the runtime, SDK, and
Electron BaseApp declared in the manifest). If `flatpak-builder` isn't on your
`PATH` it falls back to `nix shell nixpkgs#flatpak-builder nixpkgs#appstream`.

To build manually:

```sh
flatpak-builder --user --install-deps-from=flathub --install --force-clean \
  build-dir me.jezh.ClaudeDesktop.yaml
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
`me.jezh.ClaudeDesktop.yaml`.

### Automated updates

`.github/workflows/update.yml` runs `update-version.sh` daily and opens a PR
when a newer release exists. It opens the PR with a **GitHub App** installation
token rather than the default `GITHUB_TOKEN`, so the PR is not caught by
GitHub's anti-recursion rule and the **Build** workflow verifies it
automatically.

One-time setup:

1. Create a GitHub App (Settings → Developer settings → GitHub Apps → New).
   Give it repository permissions **Contents: Read and write** and
   **Pull requests: Read and write**. No webhook needed.
2. Generate a private key for the App and note its App ID.
3. Install the App on this repository.
4. Add two repository secrets (Settings → Secrets and variables → Actions):
   - `APP_ID` — the App's numeric id
   - `APP_PRIVATE_KEY` — the full contents of the downloaded `.pem`

## What works / what doesn't

- **Chat, Claude Code** (integrated terminal, editor, diff review): work.
- **Credentials, notifications, tray icon**: wired up via the Secret Service,
  notification, and StatusNotifier D-Bus names in `finish-args`.
- **Cowork** (x86_64): **works.** The manifest builds QEMU 11.0.2 (KVM + slirp +
  virtio/vhost-user/vhost-vsock) and bundles OVMF UEFI firmware, then redirects
  the app's hardcoded `/usr/share/OVMF` firmware path to `/app/share/OVMF` via a
  same-length in-place patch of `app.asar`. The VM image, `virtiofsd`, and the
  Cowork helper come bundled in the upstream `.deb`. Requires the host
  prerequisites below. On **aarch64**, QEMU is not bundled — you get Chat +
  Claude Code but not Cowork (see "Enabling Cowork on aarch64").
- **Sandbox caveat for Claude Code:** the integrated terminal runs *inside* the
  Flatpak sandbox, so it sees the runtime's tools — not compilers/interpreters
  installed on your host (especially relevant on NixOS). `--filesystem=home`
  lets it read/write your project files and shares `~/.claude` with the CLI, but
  host toolchains aren't on `PATH` inside the sandbox. If you rely on
  host-installed dev tools, the native `.deb` or the CLI may suit you better.

## Cowork host prerequisites (x86_64)

Cowork boots a KVM microVM, so the host must expose virtualization:

- **`/dev/kvm`** must exist and be accessible to your user (usually membership
  in the `kvm` group).
- **`vhost_vsock`** kernel module must be loaded (provides `/dev/vhost-vsock`,
  used for host↔guest communication).

Flatpak has no granular option for `/dev/vhost-vsock`, so the manifest uses
`--device=all` to pass host devices through. If you don't use Cowork, you can
tighten this to `--device=dri --device=kvm` in the manifest and rebuild.

On NixOS:

```nix
# configuration.nix
virtualisation.libvirtd.enable = true;      # pulls in KVM + sets up /dev/kvm perms
boot.kernelModules = [ "kvm-amd" "vhost_vsock" ];   # use kvm-intel on Intel CPUs
users.users.<you>.extraGroups = [ "kvm" ];
```

Verify from inside the sandbox after install:

```sh
flatpak run --command=sh me.jezh.ClaudeDesktop -c \
  'ls -l /dev/kvm /dev/vhost-vsock; qemu-system-x86_64 --version'
```

### Enabling Cowork on aarch64

The `libslirp`, `qemu`, and `ovmf` modules are marked `only-arches: [x86_64]`.
To support Cowork on aarch64 you'd change those to `aarch64`, build QEMU with
`--target-list=aarch64-softmmu` (which additionally needs a `dtc`/libfdt module,
since aarch64 uses device trees — unlike x86 it can't be `--disable-fdt`'d), and
ship the AAVMF firmware (Debian `qemu-efi-aarch64`) as `/app/share/AAVMF/AAVMF_CODE.fd`
+ `AAVMF_VARS.fd`. This path is untested here.

## Updating QEMU

`update-version.sh` bumps only Claude itself. QEMU, libslirp, OVMF, and the two
pip wheels are pinned by hand in the manifest — bump their `url`/`sha256` there
when you want newer versions.

## Permissions

See `finish-args` in the manifest. Notably `--filesystem=home` is broad; narrow
it to specific project directories (e.g. `--filesystem=~/code`) if you want
tighter isolation. `--device=all` is required for Cowork (see above).

## How it works

1. `flatpak-builder` downloads the official per-arch `.deb` (checksum-pinned).
2. The `.deb` (an `ar` archive) is unpacked with `ar` + `tar` from the SDK.
3. `usr/lib/claude-desktop` is copied to `/app/lib/claude-desktop`; the SUID
   `chrome-sandbox` is dropped (zypak replaces it).
4. A wrapper (`claude-desktop.sh`) launches the Electron binary via
   `zypak-wrapper`.
5. Upstream's `.desktop` (kept for the `claude://` handler + actions) and icons
   are renamed to the app-id and exported.
6. For Cowork (x86_64): `libslirp` and `qemu` are built from source and OVMF
   firmware is extracted from Debian's `ovmf-generic` deb into `/app/share/OVMF`.
   `app.asar` is then byte-patched to redirect the app's hardcoded `/usr` lookups
   into `/app`: the firmware search path (`/usr/share/OVMF` → `/app/share/OVMF`)
   and the system virtiofsd path (`/usr/libexec/virtiofsd` → `/app/libexec/virtiofsd`,
   symlinked to the copy bundled in the `.deb`; the app otherwise only uses its
   bundled virtiofsd on Ubuntu 22.04). Every replacement is the same byte length
   (`/usr/` == `/app/`), so the archive's offset table stays valid — no repack.

## Disclaimer

Not affiliated with or endorsed by Anthropic. "Claude" and related marks belong
to Anthropic. This repository only contains packaging metadata — no Anthropic
code or binaries are redistributed here; they are fetched from Anthropic's
servers at build time.
