# Nix sudoless bootstrap (Phase 5)

Hosts where the Determinate / multi-user Nix installer can't run because
the user lacks root. Picks the lowest-overhead bootstrap that still
gives us the same home-manager config as a sudo Linux host.

## Decision tree

Run the preflight first:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/shonenm/dotfiles/main/scripts/nix-preflight.sh)
```

(or `bash ~/dotfiles/scripts/nix-preflight.sh` if dotfiles already on the host)

The script prints one of:

| preflight result | bootstrap path | what to do |
|-----------------|----------------|------------|
| `READY-NATIVE` | Determinate installer | not a sudoless host — use [linux-apt-residue.md](linux-apt-residue.md) |
| `READY-CHROOT` | nix-user-chroot | section A below |
| `READY-PORTABLE` | nix-portable | section B below |
| `BLOCKED` | none | use pixi only (section C) |

## Section A — `nix-user-chroot` (user namespaces available)

`nix-user-chroot` creates a tiny `/nix` mount in the user's namespace
without needing root. The same home-manager config from
`#matsushimakouta@linux-x86_64` works unmodified.

```bash
# 1. Install nix-user-chroot (single static binary, no root needed)
NUC_VERSION="1.3.1"
NUC_ARCH="$(uname -m)"
curl -fsSL "https://github.com/nix-community/nix-user-chroot/releases/download/${NUC_VERSION}/nix-user-chroot-bin-${NUC_VERSION}-${NUC_ARCH}-unknown-linux-musl" \
  -o ~/.local/bin/nix-user-chroot
chmod +x ~/.local/bin/nix-user-chroot

# 2. Allocate a user-owned /nix directory (lives at ~/.nix-store/nix)
mkdir -p ~/.nix-store/nix

# 3. Enter the chroot and run the regular Nix installer
nix-user-chroot ~/.nix-store/nix bash -lc '
  curl -L https://nixos.org/nix/install | sh -s -- --no-daemon
  . ~/.nix-profile/etc/profile.d/nix.sh
  nix-shell -p nix-info --run "nix-info -m"
'

# 4. Make sure dotfiles is at ~/dotfiles (path is hardcoded in some
#    home-manager modules — nvim, claude, pi, gh — via mkOutOfStoreSymlink).
[ -e ~/dotfiles ] || ln -s ~/ghq/github.com/shonenm/dotfiles ~/dotfiles

# 5. Activate home-manager from within the chroot
nix-user-chroot ~/.nix-store/nix bash -lc '
  . ~/.nix-profile/etc/profile.d/nix.sh
  cd ~/dotfiles
  nix run home-manager/master -- switch --flake .#matsushimakouta@linux-x86_64
'
```

For ease of use, wrap the `nix-user-chroot ~/.nix-store/nix` prefix in a shell alias
inside `~/.zshrc.local` or similar so every Nix-managed binary is reachable.

## Section B — `nix-portable` (no user namespaces, proot fallback)

`nix-portable` is a single self-extracting binary that bundles Nix with
its own proot/bubblewrap implementation. ~3x slower than nix-user-chroot
but works on hosts where user namespaces are disabled (some kernel
configurations + corporate locked-down Linux).

```bash
# 1. Download nix-portable
curl -L https://github.com/DavHau/nix-portable/releases/latest/download/nix-portable-$(uname -m) \
  -o ~/.local/bin/nix-portable
chmod +x ~/.local/bin/nix-portable

# 2. Ensure dotfiles is at ~/dotfiles (mkOutOfStoreSymlink hardcoded path)
[ -e ~/dotfiles ] || ln -s ~/ghq/github.com/shonenm/dotfiles ~/dotfiles

# 3. Activate home-manager via nix-portable
cd ~/dotfiles
~/.local/bin/nix-portable nix run home-manager/master -- \
  switch --flake .#matsushimakouta@linux-x86_64
```

Notes:
- `nix-portable` keeps its store at `~/.nix-portable/store` by default.
- Build performance is degraded — fine for occasional switches.
- Some kernel features (e.g. `extended-attributes`) may not be available;
  most home-manager modules don't need them.

## Section C — Pixi only (Nix bootstrap blocked)

If preflight reports `BLOCKED` (no namespaces, no proot fallback, kernel
too old, SELinux/AppArmor blocking proot), give up on Nix and keep using
the existing pixi-based no-sudo flow:

- `config/pixi-packages.txt` lists what to install
- `scripts/install-in-container.sh` handles the bootstrap
- `~/.pixi/bin` is already in PATH via legacy `.zshrc.common` PATH line
  (still present on Linux hosts; only the mac sudo path migrated to Nix)

This is the same setup the repo had pre-Nix migration. Documented as a
permanent fallback rather than something we plan to remove.

## What survives across bootstrap modes

All three Nix bootstrap modes (`READY-NATIVE`, `READY-CHROOT`,
`READY-PORTABLE`) use **the same** `homeConfigurations."matsushimakouta@linux-..."`
output from `flake.nix`. Don't fork the home-manager config per bootstrap
mode — the difference is just *how* `nix` gets invoked, not *what* it
builds.

## Verification after bootstrap

Same checks regardless of mode:

```bash
which fd          # → ~/.nix-profile/bin/fd  (or ~/.nix-portable/...)
which starship   # → ~/.nix-profile/bin/starship
echo $ZSH_VERSION # → should be the Nix-managed zsh
abbr list | wc -l # → 66
```
