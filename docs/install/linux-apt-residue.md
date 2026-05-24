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
3. Clone dotfiles and activate home-manager:
   ```bash
   ghq get shonenm/dotfiles
   cd ~/ghq/github.com/shonenm/dotfiles
   nix run home-manager/master -- switch --flake .#matsushimakouta@linux-x86_64
   ```

See also: `docs/install/nix-sudoless-bootstrap.md` for hosts where step 2 is not possible.
