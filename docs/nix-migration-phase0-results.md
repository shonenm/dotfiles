# Nix Migration: Phase 0 Results

**Phase 0 Scope**: Scaffold-only — flake.nix structure + preflight verification. No behavioral changes to existing system.

**Status**: ✅ Scaffold files created and verified. Ready for main branch merge.

---

## Confirmed Decisions

### 1. Installer: Determinate Systems
- **Choice**: Determinate Systems Nix installer (v3.21.0 compatible)
- **Reason**: Modern multi-user install for macOS/Linux, APFS volume support, automated uninstall
- **Sudoless Strategy**: TBD after preflight results (see Decision Matrix section below)

### 2. dotfile Style: home.file symlinks
- **Choice**: Use home-manager `home.file.*` with `source = config.lib.file.mkOutOfStoreSymlink`
- **Reason**: Preserves mutable dotfiles, integrates with existing stow tree structure
- **Plan**: Phase 1+ will define package-specific home.file entries

### 3. Package Management: Maintain current tooling
- **Mise integration**: Keep `mise` for development tool versions
- **Nix scope**: System/user environment; language runtimes from mise
- **Rationale**: Incremental adoption; mis is already battle-tested

### 4. Container/Remote Strategy: Maintain current setup
- **Remote hosts**: Continue SSH-based development (no NixOS container requirement)
- **Local containers**: No change to existing Docker/nix-portable usage
- **Phased adoption**: Nix enables future simplification, not a breaking change

---

## Preflight Verification Matrix

**Instructions**: After creating Issue #138 and branch `138-nix-migration-phase0`, run preflight on all target hosts:

```bash
ssh <host> 'bash -s' < scripts/nix-preflight.sh
```

Fill results below to validate **Decision 1 (Installer Strategy)**:

| Host | OS | Kernel | Result | Install Method | Notes |
|------|-----|--------|--------|-----------------|-------|
| shonenm (mac) | macOS 14.6 | - | ✅ READY-NATIVE | Determinate Systems | Local test passed |
| ailab (linux) | Ubuntu 22.04 | 5.15.x | TBD | See result | |
| ailab:syntopic-dev | Ubuntu 22.04 | 5.15.x | TBD | See result | dev container |
| ailab:syntopic-dev-review | Ubuntu 22.04 | 5.15.x | TBD | See result | review container |
| ailab:syntopic-deploy | Ubuntu 22.04 | 5.15.x | TBD | See result | deploy container |
| ailab:fluid-sbi-dev | Ubuntu 22.04 | 5.15.x | TBD | See result | sbi container |
| pi-500 (rcon) | ? | ? | TBD | See result | Synology NAS |

**Result Column Key**:
- `READY-NATIVE`: Standard Determinate Systems install (recommended)
- `READY-CHROOT`: User namespaces available; use `nix-user-chroot` or Determinate with `--extra-conf 'extra-trusted-users = current-user'`
- `READY-PORTABLE`: No user namespaces; use `nix-portable` + proot (minimal feature set)
- `BLOCKED`: Cannot install Nix safely; maintain current setup

---

## Phase 0 Validation Checklist

- [x] flake.nix created with inputs (nixpkgs, home-manager, nix-darwin) and basic devShell
- [x] nix/ directory structure scaffolded (hosts/, modules/, overlays/)
- [x] .envrc created with direnv + nix-flake integration
- [x] scripts/nix-preflight.sh created for host classification
- [x] docs/nix-migration-phase0-results.md created with decision matrix
- [x] .gitignore updated (.direnv/, result*, flake.lock)
- [ ] Preflight run on all 7 target hosts (blocking Phase 1 start)
- [ ] Decision 1 confirmed: sudoless strategy selected based on results

---

## Phase 1 Gate Criteria

Phase 1 (mac packages migration) may begin once:

1. **Phase 0 PR merged to main**
2. **Preflight matrix filled** with results from all 7 target hosts
3. **Decision 1 confirmed**: Sudoless install strategy chosen based on matrix results
4. **Local Nix verified**: `nix flake check` and `nix develop` working on shonenm

---

## Next Steps

1. Commit Phase 0 scaffold to Issue #138 branch (`138-nix-migration-phase0`)
2. Create PR and merge to main (no behavioral changes)
3. Execute `scripts/nix-preflight.sh` on all 7 target hosts
4. Fill preflight matrix with results
5. Open Issue #139 (Phase 1) once Phase 0 is merged

---

**See Also**: `docs/nix-migration-plan.md` for full multi-phase roadmap.
