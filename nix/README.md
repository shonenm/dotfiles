# nix/

Nix migration tree. See `docs/nix-migration-plan.md` for the full plan.

## Layout

```
nix/
├── hosts/                 # Per-host entrypoints (mac, linux-sudo, linux-rootless)
├── modules/
│   ├── packages/          # Package sets (core, mac, linux)
│   ├── programs/          # programs.* declarations (zsh, tmux, ...)
│   ├── darwin/            # nix-darwin-only modules (system defaults, brew casks, launchd)
│   └── dotfiles.nix       # home.file declarations bridging legacy stow tree
└── overlays/              # Packages not in nixpkgs (genshijin, dops, quay, lemonade, ...)
```

## Phase status

- **Phase 0 (current)**: scaffold only — flake.nix + empty subdirs. Nothing is wired to a host yet.
- Phase 1+: real configurations land here.

## Local workflow

Once Nix is installed and `direnv allow` is run in the dotfiles root:

```bash
nix flake check              # validate flake structure
nix develop                  # enter devShell (jq, nixpkgs-fmt, statix)
nix fmt                      # format *.nix files
```
