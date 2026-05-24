# Linux apt residue (Phase 4/5)

Packages that **stay on apt** after the Nix migration. Home-manager
covers user-level tooling; these stay outside Nix because they're
system-level, require setuid/system services, are too large to ship per
user, or behave better when integrated with the host distro's package
manager.

## Stays on apt

| package | reason |
|---------|--------|
| `build-essential`, `pkg-config`, `libssl-dev` | system C toolchain; needed by some build-from-source paths; trivially installable via apt |
| `postgresql` (server) | system service with `postgres` user, systemd unit, data dir at `/var/lib/postgresql`. Use Nix's `pgcli` client + apt server. |
| `openssh-server` | system service; needs setuid for keys; apt's openssh-server registers a launchd-equivalent service |
| `zsh` | declared in `/etc/passwd` as login shell; system zsh is what `login(1)` execs. Nix-managed zsh also installed (programs.zsh.enable), referenced via PATH. |
| fonts (PlemolJP, Nerd Fonts, etc.) | installed system-wide via apt or `fc-cache`; share across all users |
| `luarocks` | needed by Neovim plugin packaging in some Lua plugin builds; apt's version is fine |
| `imagemagick` (system) | sometimes pulled by system services / cron; Nix's imagemagick coexists in user PATH |

## Replaced by Nix (home-manager)

Everything else from the previous apt list (`config/packages.linux.apt.txt`) is now installed via Nix home-manager:

| previously apt | now Nix |
|---------------|---------|
| ripgrep, fd-find | `nix/modules/packages/linux.nix` |
| jq, stow, unzip | `nix/modules/packages/linux.nix` |
| tmux | `programs.tmux.enable = true` |
| autossh, pueue | `nix/modules/packages/linux.nix` |
| ghq, gh | `nix/modules/packages/linux.nix` / `programs.gh.enable = true` |
| eza, bat, lazygit | `programs.<name>.enable = true` |

## Setup steps for a fresh ailab-style Linux host

1. Install apt residue:
   ```bash
   sudo apt update && sudo apt install -y \
     build-essential pkg-config libssl-dev \
     postgresql openssh-server zsh \
     luarocks fontconfig
   ```
2. Install Nix (Determinate Systems installer):
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
   ```
3. Clone dotfiles **to `~/dotfiles`** (mandatory path — see "Path assumption" below):
   ```bash
   git clone https://github.com/shonenm/dotfiles.git ~/dotfiles
   # or, if ghq is your convention, symlink:
   #   ghq get shonenm/dotfiles && ln -s ~/ghq/github.com/shonenm/dotfiles ~/dotfiles
   cd ~/dotfiles
   nix run home-manager/master -- switch --flake .#matsushimakouta@linux-x86_64
   ```

## Migrating from legacy stow setup

If the host previously ran the stow-based install (pre-Nix), absolute symlinks like `~/.config/atuin → ~/dotfiles/common/atuin/.config/atuin` may remain. `stow -D` silently skips absolute symlinks, so they linger. **Worse**: when home-manager activation writes to e.g. `~/.config/atuin/config.toml`, it follows the dir symlink and overwrites the actual `common/atuin/.config/atuin/config.toml` source file with a `/nix/store/...` symlink — corrupting the repo source.

Clean up before first home-manager activation:

```bash
# Detect leftover stow dir symlinks pointing into dotfiles
for d in ~/.config/*; do
  [ -L "$d" ] || continue
  case "$(readlink "$d")" in
    */dotfiles/*) echo "remove: $d"; rm "$d" ;;
  esac
done
# Same for top-level dotfiles (~/.gitconfig pre-Nix etc. — usually relative
# stow symlinks, those get cleaned by `stow -D` fine; only absolutes linger)
```

## Path assumption

Several home-manager modules (nvim, claude, pi, gh) use `mkOutOfStoreSymlink` to point at `${config.home.homeDirectory}/dotfiles/...`. The path is hardcoded. If the repo lives elsewhere on the host, either:
- Symlink: `ln -s ~/ghq/github.com/shonenm/dotfiles ~/dotfiles`
- Or change the clone target to `~/dotfiles` directly.

See also: `docs/install/nix-sudoless-bootstrap.md` for hosts where step 2 is not possible.
