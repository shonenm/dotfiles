#!/bin/bash
set -euo pipefail

# Dotfiles root directory
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utilities
source "$DOTFILES_DIR/scripts/utils.sh"

# --- Argument Parsing ---
# NO_SUDO defaults to false (use sudo/system path).
# Pass --no-sudo to opt into pixi-based user-scope install on sudoless hosts.
# Pass --update to refresh remote dependencies even when their inputs are unchanged.
SKIP_PROMPT=false
NO_SUDO=false
SKIP_1P=false
UPDATE_INSTALL=false
SETUP_FAILED=false
NOT_SIGNED_IN=false
OP_SIGNED_IN=false
for arg in "$@"; do
  case "$arg" in
    -y|--skip-prompt) SKIP_PROMPT=true ;;
    --no-sudo)        NO_SUDO=true ;;
    --skip-1p)        SKIP_1P=true ;;
    --update)         UPDATE_INSTALL=true ;;
  esac
done
export NO_SUDO SKIP_1P UPDATE_INSTALL

# ~/.local/bin を PATH 先頭に追加。no-sudo install したツール (op など) を
# install.sh プロセス全体で参照可能にし、再実行時の不要な再インストールを防ぐ。
# (interactive shell では dotfiles の zsh 設定が同じことをするが、stow 前は未反映)
export PATH="$HOME/.local/bin:$PATH"

# --- 1. 1Password CLI Check ---
install_1password_cli() {
  local os
  os=$(detect_os)

  if [[ "$os" == "mac" ]]; then
    if command_exists brew; then
      log_info "Installing 1Password CLI via Homebrew..."
      brew install 1password-cli
    else
      log_error "Homebrew not found. Please install Homebrew first."
      exit 1
    fi
  elif [[ "$os" == "linux" ]]; then
    if [[ "$NO_SUDO" == "true" ]]; then
      _install_1password_cli_user_scope
    elif command_exists apt; then
      log_info "Installing 1Password CLI via apt..."
      # Setup SUDO
      local SUDO=""
      [[ $EUID -ne 0 ]] && SUDO="sudo"

      # Add 1Password apt repository
      curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
        $SUDO gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg 2>/dev/null || true

      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
        $SUDO tee /etc/apt/sources.list.d/1password.list >/dev/null

      $SUDO apt update
      $SUDO apt install -y 1password-cli
    else
      log_error "apt not found. Please install 1Password CLI manually:"
      echo "  https://developer.1password.com/docs/cli/get-started/"
      exit 1
    fi
  else
    log_error "Unsupported OS. Please install 1Password CLI manually."
    exit 1
  fi
}

# Install 1Password CLI to ~/.local/bin without sudo (tarball from cache.agilebits.com)
_install_1password_cli_user_scope() {
  local arch
  case "$(uname -m)" in
    x86_64)         arch="amd64" ;;
    aarch64|arm64)  arch="arm64" ;;
    *)              log_error "Unsupported arch for 1Password CLI: $(uname -m)"; return 1 ;;
  esac

  # Resolve latest version from AgileBits update API (fall back to known-good if API/json fails)
  local version="${OP_CLI_VERSION:-}"
  if [[ -z "$version" ]]; then
    version=$(curl -fsSL 'https://app-updates.agilebits.com/check/1/0/CLI2/en/0/N' 2>/dev/null \
      | python3 -c 'import sys,json; print(json.load(sys.stdin).get("version",""))' 2>/dev/null \
      || true)
  fi
  version="${version:-2.33.1}"

  local zip; zip="$(mktemp -t op.XXXXXX.zip)"
  local url="https://cache.agilebits.com/dist/1P/op2/pkg/v${version}/op_linux_${arch}_v${version}.zip"

  log_info "Installing 1Password CLI v${version} (user-scope, no sudo)..."
  mkdir -p "$HOME/.local/bin"
  if ! curl -fsSL "$url" -o "$zip"; then
    log_error "Failed to download 1Password CLI from $url"
    log_error "Override version with OP_CLI_VERSION env var (see https://app-updates.agilebits.com/product_history/CLI2)"
    return 1
  fi
  if ! command_exists unzip; then
    log_error "unzip not found. Install via pixi first: pixi global install unzip"
    rm -f "$zip"
    return 1
  fi
  unzip -o "$zip" op -d "$HOME/.local/bin" >/dev/null
  chmod +x "$HOME/.local/bin/op"
  rm -f "$zip"
  export PATH="$HOME/.local/bin:$PATH"
  log_success "1Password CLI installed to ~/.local/bin/op"
}

check_1password_cli() {
  # --skip-1p: container / ephemeral env で secret lookup が不要な時。
  # Notion MCP 等を使うステップは対応する op read が no-op fallback するので
  # 警告だけ出して続行する。
  if [[ "$SKIP_1P" == "true" ]]; then
    log_warn "1Password CLI check skipped (--skip-1p). Secret-dependent steps will no-op."
    return 0
  fi

  # Check if op is installed, install if not
  if ! command_exists op; then
    log_warn "1Password CLI is not installed."
    install_1password_cli
  fi

  # Check if signed in.
  #
  # 未 signin でも exit せず継続する (これが根本治療)。
  # signin gate を fatal にすると、その先の link_dotfiles (stow) に到達できず
  # ~/.zshenv がリンクされない。すると ~/.local/bin が PATH に入らず、sudoless で
  # op を入れても interactive shell から永遠に見えない (毎回フルパス回避が必要)。
  # sudo モードは op が /usr/local/bin (既に PATH) に入るのでこの問題が出ず、
  # 両モードで挙動が非対称になっていた。
  # 継続すれば stow が ~/.zshenv を配線し、次の shell で両モードとも素の `op` が通る。
  # secret 依存ステップは op read が no-op fallback するので未 signin でも安全。
  if ! op whoami &>/dev/null; then
    NOT_SIGNED_IN=true
    log_warn "1Password CLI is not signed in. Secret-dependent steps will no-op this run."
    log_warn "Sign in after install completes (see final summary), then re-run to populate secrets."
    return 0
  fi

  log_success "1Password CLI: ready"
  OP_SIGNED_IN=true
}

# --- 0. Install Homebrew (Mac only) ---
install_homebrew() {
  if [[ "$(detect_os)" != "mac" ]]; then
    return
  fi

  if command_exists brew; then
    log_success "Homebrew already installed"
    return
  fi

  log_info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # The installer does not update this non-interactive process's PATH.
  local brew_bin=""
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$candidate" ]]; then
      brew_bin="$candidate"
      break
    fi
  done
  [[ -n "$brew_bin" ]] || { log_error "Homebrew installation completed but brew was not found"; return 1; }
  eval "$("$brew_bin" shellenv)"
}

# --- 2. Setup Environment (Delegate to scripts/) ---
setup_environment() {
  local os
  os=$(detect_os)
  log_info "Detected OS: $os"

  case "$os" in
    mac)
      if [[ -f "$DOTFILES_DIR/scripts/mac.sh" ]]; then
        log_info "Running macOS setup script..."
        if ! bash "$DOTFILES_DIR/scripts/mac.sh"; then
          SETUP_FAILED=true
          log_warn "Some macOS setup steps failed (see above); continuing"
        fi
      else
        log_warn "scripts/mac.sh not found. Skipping package installation."
      fi
      ;;
    linux)
      if [[ -f "$DOTFILES_DIR/scripts/linux.sh" ]]; then
        log_info "Running Linux setup script..."
        if ! bash "$DOTFILES_DIR/scripts/linux.sh"; then
          SETUP_FAILED=true
          log_warn "Some Linux setup steps failed (see above); continuing"
        fi
      else
        log_warn "scripts/linux.sh not found. Skipping package installation."
      fi
      ;;
    *)
      log_warn "Unsupported OS. Skipping package installation."
      ;;
  esac
}

# --- 3. Link Dotfiles (Stow) ---

# Replace absolute links into this repository with links owned by Stow.
# Older installer runs created these links directly; Stow 2.4 rejects them even
# though source and target resolve to the same file.
normalize_dotfiles_symlinks() {
  local link relative resolved source
  while IFS= read -r -d '' link; do
    [[ $(readlink "$link") == /* ]] || continue
    relative=${link#"$HOME"/}
    resolved=$(realpath "$link" 2>/dev/null || true)
    for source in "$DOTFILES_DIR"/common/*/"$relative" "$DOTFILES_DIR"/mac/*/"$relative"; do
      [[ -e "$source" && "$resolved" == "$(realpath "$source")" ]] && { unlink "$link"; break; }
    done
  done < <(find "$HOME/.pi" -type l -print0 2>/dev/null)
}

# Stow a package with conflict detection and backup
stow_package() {
  local pkg_dir="$1"
  local pkg_name="$2"

  # dry-runでコンフリクトを検出
  local conflicts
  conflicts=$(stow -n --no-folding -d "$pkg_dir" -t "$HOME" "$pkg_name" 2>&1 | \
    grep "existing target" | sed 's/.*over existing target //' | sed 's/ since.*//' || true)

  # コンフリクトファイルをバックアップ
  if [[ -n "$conflicts" ]]; then
    while IFS= read -r file; do
      [[ -z "$file" ]] && continue
      local target="$HOME/$file"
      if [[ -e "$target" && ! -L "$target" ]]; then
        if mv "$target" "$target.dotfiles-bak" 2>/dev/null; then
          log_info "    Backed up: $file → $file.dotfiles-bak"
        else
          log_warn "    Cannot move $file (bind mount?), skipping $pkg_name"
          return 0
        fi
      fi
    done <<< "$conflicts"
  fi

  # restowで削除・移動済みsourceの古いsymlinkも掃除する。--adoptは残りの差分を吸収する。
  if ! stow --restow --no-folding -d "$pkg_dir" -t "$HOME" --adopt "$pkg_name" 2>/dev/null; then
    log_warn "  Failed to link $pkg_name"
    return 1
  fi
  return 0
}

# Stow all packages from one source directory in a single pair of processes.
# Fall back to the per-package path when an unusual bind mount prevents the
# aggregate operation, preserving the existing best-effort behavior.
stow_package_group() {
  local pkg_dir="$1"
  shift
  local packages=("$@") dry_run conflicts file target
  [[ ${#packages[@]} -gt 0 ]] || return 0

  dry_run=$(stow -n --no-folding -d "$pkg_dir" -t "$HOME" "${packages[@]}" 2>&1 || true)
  conflicts=$(printf '%s\n' "$dry_run" | sed -n \
    -e 's/.*over existing target //p' \
    -e 's/^[[:space:]]*\*[[:space:]]*existing target is not owned by stow: //p' | \
    sed 's/ since.*//' | sort -u)

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    target="$HOME/$file"
    if [[ -e "$target" && ! -L "$target" ]]; then
      if mv "$target" "$target.dotfiles-bak" 2>/dev/null; then
        log_info "    Backed up: $file → $file.dotfiles-bak"
      else
        log_warn "    Cannot move $file (bind mount?); using package fallback"
        local pkg failed=0
        for pkg in "${packages[@]}"; do
          stow_package "$pkg_dir" "$pkg" || failed=1
        done
        return "$failed"
      fi
    fi
  done <<< "$conflicts"

  if ! stow --restow --no-folding -d "$pkg_dir" -t "$HOME" --adopt "${packages[@]}" 2>/dev/null; then
    log_warn "  Grouped stow failed; retrying packages individually"
    local pkg failed=0
    for pkg in "${packages[@]}"; do
      stow_package "$pkg_dir" "$pkg" || failed=1
    done
    return "$failed"
  fi
}

# Remove links whose source was deleted or moved before restowing the new layout.
# Restrict cleanup to skill roots; runtime files elsewhere under ~/.pi are untouched.
cleanup_broken_skill_links() {
  local root link
  for root in "$HOME/.config/agent/skills" "$HOME/.pi/agent/skills" \
              "$HOME/.codex/skills" "$HOME/.cursor/skills"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r -d '' link; do
      if [[ ! -e "$link" ]]; then
        rm -f "$link"
        log_info "  Removed stale skill link: ${link#"$HOME/"}"
      fi
    done < <(find "$root" -type l -print0)
    find "$root" -depth -mindepth 1 -type d -empty -exec rmdir {} \; 2>/dev/null || true
  done
}

# Link shared agent skills into a runtime dest. Relink only when the existing
# link still points at common/agent skills; keep plugin/user-managed entries.
link_runtime_skills() {
  local src="$1" dest="$2" label="$3" skill_dir skill_name target_dir current
  [[ -d "$src" ]] || return 0
  mkdir -p "$dest"

  for skill_dir in "$src"/*/; do
    [[ -d "$skill_dir" ]] || continue
    skill_dir=${skill_dir%/}
    skill_name=$(basename "$skill_dir")
    target_dir="$dest/$skill_name"

    if [[ -L "$target_dir" ]]; then
      current=$(readlink "$target_dir")
      if [[ "$current" == "$skill_dir" ]]; then
        continue
      fi
      case "$current" in
        */common/agent/.config/agent/skills/"$skill_name") ;;
        *) log_warn "  Kept externally managed $label skill: $skill_name"; continue ;;
      esac
    elif [[ -e "$target_dir" ]]; then
      log_warn "  Kept unmanaged $label skill: $skill_name"
      continue
    fi

    ln -sfn "$skill_dir" "$target_dir"
    log_success "  Linked $label skill: $skill_name"
  done
}

link_codex_skills() {
  link_runtime_skills "$1" "$2" "Codex"
}

# cursor-agent reads cli-config.json from CURSOR_CONFIG_DIR, else
# $XDG_CONFIG_HOME/cursor, else ~/.cursor. mcp.json / hooks.json / rules stay
# on the data dir (~/.cursor) and are not affected.
cursor_config_dir() {
  if [[ -n "${CURSOR_CONFIG_DIR:-}" ]]; then
    printf '%s\n' "$CURSOR_CONFIG_DIR"
  elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
    printf '%s\n' "$XDG_CONFIG_HOME/cursor"
  else
    printf '%s\n' "$HOME/.cursor"
  fi
}

# Merge template keys into cli-config.json. The CLI owns the same file for
# runtime state (auth, model selection, caches), so unknown keys are preserved.
# Returns 1 when dest is already current.
write_cursor_cli_config() {
  local src="$1" dest="$2" tmp
  [[ -f "$src" ]] || return 0
  mkdir -p "$(dirname "$dest")"
  tmp=$(mktemp)
  if ! python3 - "$src" "$dest" "$HOME" >"$tmp" <<'PY'
import json, sys
from pathlib import Path

src, dest, home = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
managed = json.loads(src.read_text().replace("__HOME__", home))

live = {}
if dest.exists():
    try:
        live = json.loads(dest.read_text())
    except (OSError, ValueError):
        live = {}

def merge(base, over):
    out = dict(base)
    for key, value in over.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = merge(out[key], value)
        else:
            out[key] = value
    return out

json.dump(merge(live, managed), sys.stdout, indent=2, ensure_ascii=False)
sys.stdout.write("\n")
PY
  then
    rm -f "$tmp"
    return 1
  fi
  if [[ -f "$dest" ]] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$dest"
  chmod 600 "$dest"
}

# Upsert enabled servers from shared agent mcp.json into ~/.cursor/mcp.json.
# Extra user servers are kept. Returns 1 when dest is already current.
write_cursor_mcp() {
  local src="$1" dest="$2" tmp
  [[ -f "$src" ]] || return 0
  mkdir -p "$(dirname "$dest")"
  tmp=$(mktemp)
  if ! python3 - "$src" "$dest" "$HOME" >"$tmp" <<'PY'
import json, sys
from pathlib import Path

src, dest, home = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
servers = json.loads(src.read_text())["mcpServers"]

def resolve(value):
    if isinstance(value, str):
        return value.replace("${HOME}", home)
    if isinstance(value, list):
        return [resolve(item) for item in value]
    if isinstance(value, dict):
        return {key: resolve(item) for key, item in value.items()}
    return value

from_src = {}
for name, cfg in servers.items():
    if cfg.get("enabled", True) is False:
        continue
    entry = {key: value for key, value in cfg.items()
             if key not in ("description", "permission", "enabled")}
    from_src[name] = resolve(entry)

existing = {}
if dest.exists():
    try:
        existing = json.loads(dest.read_text()).get("mcpServers") or {}
    except (OSError, ValueError):
        existing = {}

merged = dict(existing)
merged.update(from_src)
json.dump({"mcpServers": merged}, sys.stdout, indent=2, ensure_ascii=False)
sys.stdout.write("\n")
PY
  then
    rm -f "$tmp"
    return 1
  fi
  if [[ -f "$dest" ]] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$dest"
}

# Clean up orphaned (non-symlink) files left behind in stow-managed directories.
# stow --adopt only handles files present in the stow package. Files that exist
# only in the target directory are ignored, causing stale configs to persist.
# Usage: cleanup_stow_orphans <pkg_dir> <relative_subdir>
cleanup_stow_orphans() {
  local pkg_dir="$1"     # e.g. /path/to/dotfiles/common
  local subdir="$2"      # e.g. nvim/.config/nvim/lua/plugins
  local pkg_name="${subdir%%/*}"  # e.g. nvim
  local target_dir="$HOME/${subdir#*/}"  # e.g. ~/.config/nvim/lua/plugins
  local source_dir="$pkg_dir/$subdir"

  [[ -d "$target_dir" ]] || return 0
  [[ -d "$source_dir" ]] || return 0

  local orphans_found=false
  for file in "$target_dir"/*.lua; do
    [[ -e "$file" ]] || continue
    # Skip symlinks (managed by stow) and backup files
    [[ -L "$file" ]] && continue
    [[ "$file" == *.dotfiles-bak ]] && continue

    local basename
    basename="$(basename "$file")"

    # Only remove if there's no corresponding file in the stow source
    if [[ ! -e "$source_dir/$basename" ]]; then
      if ! $orphans_found; then
        log_info "  Cleaning up orphaned files in ~/${subdir#*/}/"
        orphans_found=true
      fi
      mv "$file" "$file.dotfiles-bak"
      log_info "    Backed up orphan: $basename → $basename.dotfiles-bak"
    fi
  done
}

# Verify critical symlinks were created
verify_stow() {
  local failed=()
  local checks=(
    ".config/tmux"
    ".config/mise"
    ".config/nvim"
    ".config/starship.toml"
  )

  for path in "${checks[@]}"; do
    # Check if path exists as symlink or directory (stow creates symlinks to dirs)
    if [[ ! -L "$HOME/$path" && ! -e "$HOME/$path" ]]; then
      failed+=("$path")
    fi
  done

  if [[ ${#failed[@]} -gt 0 ]]; then
    echo
    log_warn "Some dotfiles may not be linked correctly:"
    for f in "${failed[@]}"; do
      log_warn "  - ~/$f"
    done
    log_info "Try running manually: stow -v -t ~ -d common <package>"
    log_info "Or check for conflicts with: stow -n -v -t ~ -d common <package>"
  fi
}

# Fixup bind-mounted config files that stow couldn't replace
fixup_bind_mounts() {
  # .gitconfig: inject [include] to pull in dotfiles gitconfig
  local dotfiles_gitconfig="$DOTFILES_DIR/common/git/.gitconfig"
  if [[ -f "$HOME/.gitconfig" && ! -L "$HOME/.gitconfig" && -f "$dotfiles_gitconfig" ]]; then
    if ! grep -qF "path = $dotfiles_gitconfig" "$HOME/.gitconfig" 2>/dev/null; then
      if [[ -w "$HOME/.gitconfig" ]]; then
        printf '\n[include]\n    path = %s\n' "$dotfiles_gitconfig" >> "$HOME/.gitconfig"
        log_info "  Injected [include] into bind-mounted .gitconfig"
      else
        # Fallback: Git reads both ~/.gitconfig and $XDG_CONFIG_HOME/git/config
        local xdg_git_config="${XDG_CONFIG_HOME:-$HOME/.config}/git/config"
        mkdir -p "$(dirname "$xdg_git_config")"
        if ! grep -qF "path = $dotfiles_gitconfig" "$xdg_git_config" 2>/dev/null; then
          printf '[include]\n    path = %s\n' "$dotfiles_gitconfig" >> "$xdg_git_config"
        fi
        log_info "  .gitconfig is read-only, wrote [include] to $xdg_git_config"
      fi
    else
      log_success "  .gitconfig already includes dotfiles config"
    fi
  fi

  # .ssh/config: prepend Include to pull in dotfiles ssh config
  local os
  os=$(detect_os)
  local dotfiles_ssh="$DOTFILES_DIR/$os/ssh/.ssh/config"
  if [[ -f "$HOME/.ssh/config" && ! -L "$HOME/.ssh/config" && -f "$dotfiles_ssh" ]]; then
    if ! grep -qF "Include $dotfiles_ssh" "$HOME/.ssh/config" 2>/dev/null; then
      if [[ -w "$HOME/.ssh/config" ]]; then
        local tmp
        tmp=$(mktemp)
        printf 'Include %s\n\n' "$dotfiles_ssh" > "$tmp"
        cat "$HOME/.ssh/config" >> "$tmp"
        cp "$tmp" "$HOME/.ssh/config"
        rm "$tmp"
        log_info "  Injected Include into bind-mounted .ssh/config"
      else
        log_warn "  .ssh/config is read-only, skipping injection"
      fi
    else
      log_success "  .ssh/config already includes dotfiles config"
    fi
  fi
}

link_dotfiles() {
  log_info "Linking dotfiles..."

  # Check if stow is installed
  if ! command_exists stow; then
    log_error "Stow is not installed. Skipping linking."
    log_warn "Please check if setup scripts ran correctly."
    return 1
  fi

  local os link_failed=false
  os=$(detect_os)

  # Abort if the repo has uncommitted changes under the stow source dirs.
  # stow --adopt overwrites repo files with the $HOME versions, and the
  # later `git checkout -- common/ <os>/` rolls everything back to HEAD,
  # so any uncommitted edits would be silently destroyed.
  local dirty
  dirty=$(git -C "$DOTFILES_DIR" status --porcelain -- common/ "$os/" 2>/dev/null || true)
  if [[ -n "$dirty" ]]; then
    log_error "Uncommitted changes in dotfiles repo would be lost by stow --adopt:"
    echo "$dirty"
    log_error "Commit or stash these changes, then re-run install.sh"
    return 1
  fi

  # Create .config if not exists
  mkdir -p "$HOME/.config"
  cleanup_broken_skill_links
  normalize_dotfiles_symlinks

  # Stow common packages
  if [[ -d "$DOTFILES_DIR/common" ]]; then
    log_info "Linking common dotfiles..."
    local common_packages=()
    for pkg in "$DOTFILES_DIR/common"/*/; do
      git -C "$DOTFILES_DIR" ls-files --error-unmatch "${pkg#"$DOTFILES_DIR"/}" >/dev/null 2>&1 || continue
      common_packages+=("$(basename "$pkg")")
    done
    if ! stow_package_group "$DOTFILES_DIR/common" "${common_packages[@]}"; then
      link_failed=true
    fi
  fi

  # Stow OS-specific packages
  if [[ -d "$DOTFILES_DIR/$os" ]]; then
    log_info "Linking $os-specific dotfiles..."
    local os_packages=()
    for pkg in "$DOTFILES_DIR/$os"/*/; do
      git -C "$DOTFILES_DIR" ls-files --error-unmatch "${pkg#"$DOTFILES_DIR"/}" >/dev/null 2>&1 || continue
      os_packages+=("$(basename "$pkg")")
    done
    if ! stow_package_group "$DOTFILES_DIR/$os" "${os_packages[@]}"; then
      link_failed=true
    fi
  fi

  # Fixup bind-mounted config files (Docker/devcontainer)
  fixup_bind_mounts

  # Restore dotfiles after adopt (adopted files may have overwritten our dotfiles)
  log_info "Restoring dotfiles from git..."
  git -C "$DOTFILES_DIR" checkout -- common/ 2>/dev/null || true
  [[ -d "$DOTFILES_DIR/$os" ]] && git -C "$DOTFILES_DIR" checkout -- "$os/" 2>/dev/null || true

  # Clean up orphaned files in stow-managed directories
  # stow --adopt only handles files that exist in both source and target.
  # Files that exist only in the target (e.g. pre-stow nvim plugin configs) are left behind
  # and can interfere with the dotfiles config (LazyVim loads all lua/plugins/*.lua files).
  cleanup_stow_orphans "$DOTFILES_DIR/common" "nvim/.config/nvim/lua/plugins"
  cleanup_stow_orphans "$DOTFILES_DIR/common" "nvim/.config/nvim/lua/config"

  # Create empty .gitconfig.local if not exists (for machine-specific git user settings)
  if [[ ! -f "$HOME/.gitconfig.local" ]]; then
    touch "$HOME/.gitconfig.local"
    log_info "Created ~/.gitconfig.local for machine-specific git settings"
    log_info "Run 'setup_git_from_op' to configure git user from 1Password"
  fi

  # Verify critical symlinks were created
  verify_stow

  if [[ "$link_failed" == "true" ]]; then
    SETUP_FAILED=true
    log_error "Some dotfiles could not be linked"
  else
    log_success "Dotfiles linked successfully"
  fi
}

# --- 3.7. Setup tmux plugins (TPM + tmux-which-key) ---
setup_tmux_plugins() {
  local tpm_path="$HOME/.tmux/plugins/tpm"

  # Install TPM if not present
  if [[ ! -d "$tpm_path" ]]; then
    log_info "Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm "$tpm_path"
  fi

  # Install TPM plugins (non-interactive)
  if [[ -x "$tpm_path/bin/install_plugins" ]]; then
    log_info "Installing tmux plugins via TPM..."
    "$tpm_path/bin/install_plugins" >/dev/null 2>&1 || true
  fi

  # tmux-palette: patch makeColors() for a transparent background. The plugin
  # paints every row with an opaque RGB panel color; rewriting panel/bg to the
  # ANSI default-background code (\x1b[49m) lets Ghostty's background-image show
  # through, matching the other tmux popups. The selected-row highlight keeps
  # its color. Re-applied here because TPM updates overwrite the plugin source.
  local palette_theme="$HOME/.tmux/plugins/tmux-palette/src/theme.ts"
  if [[ -f "$palette_theme" ]]; then
    if grep -q 'panel: "\\x1b\[49m"' "$palette_theme"; then
      log_info "tmux-palette transparency patch already applied"
    elif grep -q 'panel: bg(theme.panel),' "$palette_theme"; then
      perl -i -pe 's/bg: bg\(theme\.bg\),/bg: "\\x1b[49m",/; s/panel: bg\(theme\.panel\),/panel: "\\x1b[49m",/' "$palette_theme"
      log_success "Applied tmux-palette transparency patch"
    else
      log_warn "tmux-palette theme.ts changed upstream; transparency patch skipped (re-check makeColors)"
    fi
  fi

  # Setup tmux-which-key config symlink
  local whichkey_plugin="$HOME/.tmux/plugins/tmux-which-key"
  local whichkey_config="$HOME/.config/tmux/plugins/tmux-which-key/config.yaml"
  if [[ -d "$whichkey_plugin" && -f "$whichkey_config" ]]; then
    ln -sf "$whichkey_config" "$whichkey_plugin/config.yaml"
    log_info "Linked tmux-which-key config"

    # Rebuild tmux-which-key menu (requires Python)
    if command_exists python3 && [[ -x "$whichkey_plugin/plugin.sh.tmux" ]]; then
      log_info "Building tmux-which-key menu..."
      "$whichkey_plugin/plugin.sh.tmux" >/dev/null 2>&1 || true
    fi
  fi

  # tmux-thumbs: build Rust binary if cargo is available
  local thumbs_plugin="$HOME/.tmux/plugins/tmux-thumbs"
  if [[ -d "$thumbs_plugin" ]] && command_exists cargo; then
    if [[ ! -x "$thumbs_plugin/target/release/thumbs" ]]; then
      log_info "Building tmux-thumbs..."
      (cd "$thumbs_plugin" && cargo build --release) >/dev/null 2>&1 || true
    fi
  fi

  log_success "tmux plugins installed"
}

# --- 3.8. Link dotfiles repo's git hooks ---
# scripts/git-hooks/* are committed in the repo. Link them into .git/hooks/
# so they run on git operations against the dotfiles repo itself. Currently:
#   - post-merge: broadcasts `tmux source-file` to all running tmux servers
#                 after `git pull`, so config edits propagate live.
setup_git_hooks() {
  local hooks_src="$DOTFILES_DIR/scripts/git-hooks"
  local hooks_dst="$DOTFILES_DIR/.git/hooks"

  [[ -d "$hooks_src" ]] || return 0
  [[ -d "$hooks_dst" ]] || return 0

  for hook in "$hooks_src"/*; do
    [[ -f "$hook" ]] || continue
    local name; name="$(basename "$hook")"
    ln -sf "$hook" "$hooks_dst/$name"
    log_info "Linked git hook: $name"
  done
}

# --- 4. Generate AI CLI configs from templates ---
# These configs need absolute paths for hooks to work in non-interactive shells
generate_ai_cli_configs() {
  log_info "Generating AI CLI configs..."

  # Preserve existing secret-derived settings during unsigned/--skip-1p runs.
  local secrets_available=false
  local notion_placeholder="\${NOTION_TOKEN}"
  if [[ "$SKIP_1P" != "true" && "$OP_SIGNED_IN" == "true" ]]; then
    secrets_available=true
  fi

  local templates_dir="$DOTFILES_DIR/templates"

  # Claude CLI — merge the template into the existing settings instead of
  # regenerating from scratch. Template keys win (single source of truth),
  # but keys only present locally (model, feedbackSurveyState, ...) are preserved.
  if [[ -f "$templates_dir/claude-settings.json" ]]; then
    mkdir -p "$HOME/.claude"
    local rendered_template
    rendered_template=$(mktemp)
    sed "s|__HOME__|$HOME|g" "$templates_dir/claude-settings.json" > "$rendered_template"
    python3 - "$rendered_template" "$HOME/.claude/settings.json" <<'PYEOF'
import json, sys

template_path, settings_path = sys.argv[1], sys.argv[2]
with open(template_path) as f:
    template = json.load(f)
try:
    with open(settings_path) as f:
        current = json.load(f)
except (OSError, ValueError):
    current = {}

def merge(base, override):
    out = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = merge(out[key], value)
        else:
            out[key] = value
    return out

with open(settings_path, "w") as f:
    json.dump(merge(current, template), f, indent=2, ensure_ascii=False)
    f.write("\n")
PYEOF
    rm -f "$rendered_template"
    log_success "  Merged ~/.claude/settings.json (template keys win, local-only keys kept)"
  fi

  # Claude MCP servers (from mcp.json, secrets resolved via 1Password)
  local mcp_config="$DOTFILES_DIR/common/claude/.config/claude/mcp.json"
  if [[ -f "$mcp_config" ]] && command -v claude &>/dev/null; then
    local notion_token=""
    if [[ "$secrets_available" == "true" ]]; then
      notion_token=$(op read "op://Personal/Notion MCP/credential" 2>/dev/null || true)
    fi
    local claude_mcp_fp
    claude_mcp_fp=$(install_fingerprint "file:$mcp_config" "notion:$notion_token" "home:$HOME")
    if install_state_is_current claude-mcp "$claude_mcp_fp"; then
      log_success "  Claude MCP servers already current"
    else
      # Read each server from mcp.json and register via claude mcp add-json
      python3 -c "
import json, sys
with open('$mcp_config') as f:
    servers = json.load(f)['mcpServers']
for name, config in servers.items():
    print(json.dumps({'name': name, 'config': config}))
" | while IFS= read -r entry; do
      local name config
      name=$(echo "$entry" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])")
      config=$(echo "$entry" | python3 -c "import json,sys; d=json.load(sys.stdin)['config']; print(json.dumps(d))")
      # Never register a literal unresolved secret placeholder.
      if [[ "$config" == *"$notion_placeholder"* && -z "$notion_token" ]]; then
        log_warn "  Skipped MCP server $name (Notion token unavailable)"
        continue
      fi
      if [[ -n "$notion_token" ]]; then
        config="${config//\$\{NOTION_TOKEN\}/$notion_token}"
      fi
      # Resolve ${HOME} placeholder (e.g. for cache dirs)
      config="${config//\$\{HOME\}/$HOME}"
      if claude mcp get "$name" >/dev/null 2>&1; then
        log_success "  MCP server already registered: $name"
      elif claude mcp add-json --scope user "$name" "$config" >/dev/null 2>&1; then
        log_success "  Registered MCP server: $name"
      else
        log_warn "  Failed to register MCP server: $name"
      fi
      done
      record_install_state claude-mcp "$claude_mcp_fp"
    fi
  fi

  # Claude Code skills (from common/claude, skip if Stow symlinks exist)
  local skills_src="$DOTFILES_DIR/common/claude/.claude/skills"
  if [[ -d "$skills_src" ]]; then
    mkdir -p "$HOME/.claude/skills"
    for skill_dir in "$skills_src"/*/; do
      [[ -d "$skill_dir" ]] || continue
      local skill_name
      skill_name=$(basename "$skill_dir")
      local target_dir="$HOME/.claude/skills/$skill_name"
      # Stow がディレクトリ自体をシンボリックリンクにしている場合はスキップ
      if [[ -L "$target_dir" ]]; then
        log_success "  Skill already linked: $skill_name"
        continue
      fi
      mkdir -p "$target_dir"
      local all_linked=true
      for file in "$skill_dir"*; do
        [[ -f "$file" ]] || continue
        local target_file
        target_file="$target_dir/$(basename "$file")"
        # Stow がファイル単位でシンボリックリンクにしている場合はスキップ
        if [[ -L "$target_file" ]]; then
          continue
        fi
        all_linked=false
        cp "$file" "$target_file"
      done
      if [[ "$all_linked" == "true" ]]; then
        log_success "  Skill already linked: $skill_name"
      else
        log_success "  Generated skill: $skill_name"
      fi
    done
  fi

  # Codex CLI
  if [[ -f "$templates_dir/codex-config.toml" ]]; then
    if render_home_template "$templates_dir/codex-config.toml" "$HOME/.codex/config.toml"; then
      log_success "  Generated ~/.codex/config.toml"
    else
      log_success "  ~/.codex/config.toml already current"
    fi
  fi

  # Shared Agent Skills for Codex. Keep runtime/plugin-managed entries intact.
  link_codex_skills "$DOTFILES_DIR/common/agent/.config/agent/skills" "$HOME/.codex/skills"

  # Gemini CLI
  if [[ -f "$templates_dir/gemini-settings.json" ]]; then
    if render_home_template "$templates_dir/gemini-settings.json" "$HOME/.gemini/settings.json"; then
      log_success "  Generated ~/.gemini/settings.json"
    else
      log_success "  ~/.gemini/settings.json already current"
    fi
  fi

  # Cursor CLI
  if [[ -f "$templates_dir/cursor-cli-config.json" ]]; then
    local cursor_cli_config
    cursor_cli_config="$(cursor_config_dir)/cli-config.json"
    if write_cursor_cli_config "$templates_dir/cursor-cli-config.json" "$cursor_cli_config"; then
      log_success "  Generated ${cursor_cli_config/#$HOME/~}"
    else
      log_success "  ${cursor_cli_config/#$HOME/~} already current"
    fi
  fi

  if [[ -f "$templates_dir/cursor-hooks.json" ]]; then
    if render_home_template "$templates_dir/cursor-hooks.json" "$HOME/.cursor/hooks.json"; then
      log_success "  Generated ~/.cursor/hooks.json"
    else
      log_success "  ~/.cursor/hooks.json already current"
    fi
  fi

  # Shared Agent Skills for Cursor. d-* stay on ~/.claude/skills (Cursor compat).
  link_runtime_skills "$DOTFILES_DIR/common/agent/.config/agent/skills" "$HOME/.cursor/skills" "Cursor"

  local cursor_mcp_src="$DOTFILES_DIR/common/agent/.config/agent/mcp.json"
  if [[ -f "$cursor_mcp_src" ]]; then
    if write_cursor_mcp "$cursor_mcp_src" "$HOME/.cursor/mcp.json"; then
      log_success "  Generated ~/.cursor/mcp.json"
    else
      log_success "  ~/.cursor/mcp.json already current"
    fi
  fi

  # Grok Build
  if [[ -f "$templates_dir/grok-hooks.json" ]]; then
    if render_home_template "$templates_dir/grok-hooks.json" "$HOME/.grok/hooks/tmux-agent.json"; then
      log_success "  Generated ~/.grok/hooks/tmux-agent.json"
    else
      log_success "  ~/.grok/hooks/tmux-agent.json already current"
    fi
  fi

  # Command Code CLI
  if [[ -f "$templates_dir/commandcode-settings.json" ]]; then
    if render_home_template "$templates_dir/commandcode-settings.json" "$HOME/.commandcode/settings.json"; then
      log_success "  Generated ~/.commandcode/settings.json"
    else
      log_success "  ~/.commandcode/settings.json already current"
    fi
  fi

  # Command Code skills (symlink d-* from common/claude)
  local cmd_skills_src="$DOTFILES_DIR/common/claude/.claude/skills"
  if [[ -d "$cmd_skills_src" ]]; then
    mkdir -p "$HOME/.commandcode/skills"
    for skill_dir in "$cmd_skills_src"/*/; do
      [[ -d "$skill_dir" ]] || continue
      local skill_name target_dir
      skill_name=$(basename "$skill_dir")
      target_dir="$HOME/.commandcode/skills/$skill_name"
      ln -sfn "$skill_dir" "$target_dir"
      log_success "  Linked Command Code skill: $skill_name"
    done
  fi

  # Command Code MCP servers (from shared agent mcp.json)
  local agent_mcp="$DOTFILES_DIR/common/agent/.config/agent/mcp.json"
  if [[ -f "$agent_mcp" ]] && command -v cmd &>/dev/null; then
    local notion_token=""
    if [[ "$secrets_available" == "true" ]]; then
      notion_token=$(op read "op://Personal/Notion MCP/credential" 2>/dev/null || true)
    fi
    local command_mcp_fp
    command_mcp_fp=$(install_fingerprint "file:$agent_mcp" "notion:$notion_token" "home:$HOME")
    if install_state_is_current command-mcp "$command_mcp_fp"; then
      log_success "  Command Code MCP servers already current"
    else
      python3 -c "
import json, sys
with open('$agent_mcp') as f:
    servers = json.load(f)['mcpServers']
for name, config in servers.items():
    if not config.get('enabled', True):
        continue
    cfg = {k: v for k, v in config.items()
           if k not in ('description', 'permission', 'enabled')}
    if cfg.get('type') == 'stdio':
        cfg.pop('type', None)
    print(json.dumps({'name': name, 'config': cfg}))
" | while IFS= read -r entry; do
      local name config
      name=$(echo "$entry" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])")
      config=$(echo "$entry" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['config']))")
      if [[ "$config" == *"$notion_placeholder"* && -z "$notion_token" ]]; then
        log_warn "  Skipped Command Code MCP server $name (Notion token unavailable)"
        continue
      fi
      if [[ -n "$notion_token" ]]; then
        config="${config//\$\{NOTION_TOKEN\}/$notion_token}"
      fi
      config="${config//\$\{HOME\}/$HOME}"
      if cmd mcp get "$name" >/dev/null 2>&1; then
        log_success "  Command Code MCP server already registered: $name"
      elif cmd mcp add-json --scope user "$name" "$config" >/dev/null 2>&1; then
        log_success "  Registered Command Code MCP server: $name"
      else
        log_warn "  Failed to register Command Code MCP server: $name"
      fi
      done
      record_install_state command-mcp "$command_mcp_fp"
    fi
  fi

  # Refresh secret-derived caches only when authenticated; otherwise keep the
  # last known-good values from the previous signed-in run.
  if [[ "$secrets_available" == "true" ]]; then
    local secret_cache_fp
    secret_cache_fp=$(install_fingerprint "file:$DOTFILES_DIR/scripts/ai-notify.sh" \
      "file:$DOTFILES_DIR/scripts/claude-fallback.sh")
    if install_state_is_current secret-caches "$secret_cache_fp"; then
      log_success "  Secret-derived caches already current"
    else
      log_info "  Caching webhooks..."
      for tool in claude codex gemini cursor cmd; do
        if "$DOTFILES_DIR/scripts/ai-notify.sh" --setup "$tool" 2>/dev/null; then
          log_success "    ✓ $tool webhook cached and notified"
        else
          log_warn "    ✗ $tool webhook not available"
        fi
      done

      if "$DOTFILES_DIR/scripts/claude-fallback.sh" setup 2>/dev/null; then
        log_success "  Claude fallback ready (run 'claude-fallback.sh on' during outages)"
      else
        log_warn "  Claude fallback setup skipped (API key not available)"
      fi
      record_install_state secret-caches "$secret_cache_fp"
    fi
  else
    log_warn "  Secret-derived caches and MCP credentials were not refreshed"
  fi
}

# Atuin の config と user service を stow 後に同時反映する。
# 先に service を起動すると、初回 install で daemon だけが既定 socket を使い、
# 後から固定 socket を読む client と分断される。
start_atuin_daemon() {
  local atuin_bin
  if command_exists atuin; then
    atuin_bin=$(command -v atuin)
  elif [[ -x "$HOME/.atuin/bin/atuin" ]]; then
    atuin_bin="$HOME/.atuin/bin/atuin"
  else
    return 0
  fi

  case "$(detect_os)" in
    mac)
      local plist_src plist_dst domain old_pid socket
      plist_src="$DOTFILES_DIR/templates/com.user.atuin-daemon.plist"
      plist_dst="$HOME/Library/LaunchAgents/com.user.atuin-daemon.plist"
      domain="gui/$(id -u)"
      socket="$HOME/.local/share/atuin/atuin.sock"
      old_pid=""
      [[ -f "$HOME/.local/share/atuin/atuin-daemon.pid" ]] && IFS= read -r old_pid < "$HOME/.local/share/atuin/atuin-daemon.pid"
      mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.local/state/atuin"
      sed -e "s|__HOME__|$HOME|g" -e "s|__ATUIN__|$atuin_bin|g" "$plist_src" > "$plist_dst"
      launchctl bootout "$domain/com.user.atuin-daemon" 2>/dev/null || true
      for _ in {1..25}; do
        if { [[ -z "$old_pid" ]] || ! kill -0 "$old_pid" 2>/dev/null; } && [[ ! -S "$socket" ]]; then
          break
        fi
        sleep 0.2
      done
      if { [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; } || [[ -S "$socket" ]]; then
        log_warn "Previous Atuin daemon did not stop cleanly"
        return 1
      fi
      launchctl bootstrap "$domain" "$plist_dst"
      ;;
    linux)
      if ! command_exists systemctl || ! systemctl --user show-environment >/dev/null 2>&1; then
        log_warn "systemd user session unavailable; Atuin daemon was not started"
        return 1
      fi
      systemctl --user daemon-reload
      systemctl --user enable atuin-daemon >/dev/null
      systemctl --user restart atuin-daemon
      ;;
  esac

  for _ in {1..25}; do
    if "$atuin_bin" daemon status 2>/dev/null | grep -q 'Healthy:.*true'; then
      log_success "Atuin daemon started"
      return 0
    fi
    sleep 0.2
  done
  log_warn "Atuin daemon did not become ready"
  return 1
}

# --- Main ---
main() {
  log_info "=== Dotfiles Installation Start ==="
  log_info "OS: $(detect_os)"
  log_info "Dotfiles: $DOTFILES_DIR"
  if [[ "$(detect_os)" == "linux" && "$NO_SUDO" == "true" ]]; then
    log_info "Mode: no-sudo (pixi-based user-scope install)"
  fi
  echo

  # 0. Install Homebrew first on a clean Mac; 1Password CLI uses brew.
  materialize_mise_lock
  install_homebrew

  # 1. Install/check 1Password CLI. An unsigned session only skips secrets.
  check_1password_cli

  # 2. Run environment setup (install packages)
  if [[ "$SKIP_PROMPT" == "true" ]]; then
    setup_environment
  else
    read -p "Install packages? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      setup_environment
    fi
  fi

  # 2.5. Pick up tools installed by setup_environment (subshell PATH doesn't
  # propagate back). Prepend user-scope bin dirs so subsequent steps
  # (link_dotfiles → stow, sheldon, etc) can find them.
  for d in "$HOME/.pixi/bin" "$HOME/.local/bin" "$HOME/.local/share/mise/shims" "$HOME/.cargo/bin" "$HOME/.bun/bin"; do
    [[ -d "$d" ]] && export PATH="$d:$PATH"
  done

  # 3. Link dotfiles (stow)
  link_dotfiles

  # 3.1. Start Atuin only after config and user-service definitions are linked.
  if ! start_atuin_daemon; then
    SETUP_FAILED=true
  fi

  # 3.5. Install sheldon plugins
  if command_exists sheldon; then
    local sheldon_config="$HOME/.config/sheldon/plugins.toml" sheldon_fp
    sheldon_fp=$(install_fingerprint "file:$sheldon_config")
    if install_state_is_current sheldon "$sheldon_fp"; then
      log_success "Sheldon plugins already match plugins.toml"
    else
      log_info "Installing sheldon plugins..."
      if [[ "$UPDATE_INSTALL" == "true" ]]; then
        sheldon lock --update
      else
        sheldon lock
      fi
      record_install_state sheldon "$sheldon_fp"
      log_success "Sheldon plugins installed"
    fi
  fi

  # 3.6. Regenerate tmux theme on Linux (fixes powerline char encoding)
  if [[ "$(detect_os)" == "linux" ]]; then
    log_info "Regenerating tmux theme for Linux..."
    "$DOTFILES_DIR/scripts/regenerate-tmux-theme.sh" tokyonight "$HOME/.config/tmux/tokyonight.tmux"
  fi

  # 3.7. Install TPM plugins and setup tmux-which-key
  setup_tmux_plugins

  # 3.8. Link git hooks into .git/hooks (post-merge → tmux reload broadcast)
  setup_git_hooks

  # 3.9. Install pi packages declared in ~/.pi/agent/settings.json
  install_pi_packages

  # 4. Generate AI CLI configs (with absolute paths)
  generate_ai_cli_configs

  # 4.6. Disable Serena MCP dashboard auto-open
  configure_serena_dashboard

  echo
  if [[ "$SETUP_FAILED" == "true" ]]; then
    log_error "=== Installation finished with package setup failures (see above) ==="
  else
    log_success "=== Installation Complete! ==="
  fi
  log_info "Please restart your shell or run: source ~/.zshrc"

  # 未 signin だった場合、PATH 配線済みの新 shell で signin → 再 install を案内。
  # ここまで来れば ~/.zshenv は配線済みなので、新 shell では素の `op` が通る。
  if [[ "$NOT_SIGNED_IN" == "true" ]]; then
    echo
    log_warn "1Password はまだ signin していません。新しい shell を開いて以下を実行:"
    echo "    op signin       # 新 shell なら PATH 配線済みでそのまま通る"
    if [[ "$NO_SUDO" == "true" ]]; then
      echo "    ./install.sh --no-sudo   # secret 依存ステップを再実行して反映"
    else
      echo "    ./install.sh             # secret 依存ステップを再実行して反映"
    fi
  fi

  # Unified summary (all config-driven)
  print_install_summary

  [[ "$SETUP_FAILED" == "true" ]] && exit 1
  return 0
}

# mise.lock is not stowed. mise writes host-only provenance_verified into it.
materialize_mise_lock() {
  local src="$DOTFILES_DIR/common/mise/.config/mise/mise.lock"
  local dest="$HOME/.config/mise/mise.lock"
  [[ -f "$src" ]] || return 0
  mkdir -p "$(dirname "$dest")"
  if [[ -L "$dest" ]]; then
    rm -f "$dest"
  fi
  cp "$src" "$dest"
}

# --- 3.9. Install pi packages from stowed settings.json ---
# settings.json lists npm:/git: sources; pi install is idempotent.
install_pi_packages() {
  if ! command_exists pi; then
    log_warn "pi not installed, skipping pi package install"
    return 0
  fi

  local settings_file="$HOME/.pi/agent/settings.json"
  if [[ ! -f "$settings_file" ]]; then
    log_warn "pi settings not found, skipping pi package install"
    return 0
  fi

  local packages
  packages=$(python3 -c "
import json
with open('$settings_file') as f:
    for pkg in json.load(f).get('packages', []):
        print(pkg if isinstance(pkg, str) else pkg['source'])
" 2>/dev/null) || {
    log_warn "Failed to read pi packages from settings.json"
    return 0
  }

  if [[ -z "$packages" ]]; then
    return 0
  fi

  local packages_fp
  packages_fp=$(install_fingerprint "$packages")
  if install_state_is_current pi-packages "$packages_fp"; then
    log_success "Pi packages already match settings.json"
    return 0
  fi

  log_info "Installing pi packages..."
  local package_failed=false
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    if pi install "$pkg" >/dev/null 2>&1; then
      log_success "  pi package: $pkg"
    else
      log_warn "  pi package failed: $pkg"
      package_failed=true
    fi
  done <<< "$packages"
  if [[ "$package_failed" == "false" ]]; then
    record_install_state pi-packages "$packages_fp"
  fi
}

# --- 4.6. Disable Serena MCP dashboard auto-open ---
# Serena auto-generates ~/.serena/serena_config.yml on first run with
# web_dashboard_open_on_launch: true, which pops a browser tab on startup.
# Idempotent: creates skeleton config if missing, otherwise flips the value.
configure_serena_dashboard() {
  local config_dir="$HOME/.serena"
  local config_file="$config_dir/serena_config.yml"

  mkdir -p "$config_dir"

  if [[ ! -f "$config_file" ]]; then
    log_info "Creating Serena config with dashboard auto-open disabled..."
    cat > "$config_file" <<'EOF'
web_dashboard_open_on_launch: false
EOF
    log_success "Serena dashboard auto-open disabled"
    return 0
  fi

  if grep -qE '^web_dashboard_open_on_launch:\s*false' "$config_file"; then
    log_info "Serena dashboard auto-open already disabled"
    return 0
  fi

  if grep -qE '^web_dashboard_open_on_launch:' "$config_file"; then
    sed -i.bak -E 's|^web_dashboard_open_on_launch:.*|web_dashboard_open_on_launch: false|' "$config_file"
    rm -f "${config_file}.bak"
  else
    printf '\nweb_dashboard_open_on_launch: false\n' >> "$config_file"
  fi
  log_success "Serena dashboard auto-open disabled"
}

# --- Installation Summary (reads from config files) ---
print_install_summary() {
  local os
  os=$(detect_os)
  local CONFIG_DIR="$DOTFILES_DIR/config"

  echo
  echo "────────────────────────────────────────────────────────"
  echo "  Installation Summary"
  echo "────────────────────────────────────────────────────────"

  # 1. System packages / Homebrew
  if [[ "$os" == "mac" ]]; then
    local brewfile="$CONFIG_DIR/Brewfile"
    if [[ -f "$brewfile" ]]; then
      local brew_count cask_count
      brew_count=$(grep -c '^brew ' "$brewfile" 2>/dev/null || echo 0)
      cask_count=$(grep -c '^cask ' "$brewfile" 2>/dev/null || echo 0)
      printf "  %-14s %d formulae, %d casks\n" "Homebrew" "$brew_count" "$cask_count"
    fi
  elif [[ "$os" == "linux" ]]; then
    # System packages
    if command_exists apt; then
      local pkg_file="$CONFIG_DIR/packages.linux.apt.txt"
    else
      local pkg_file="$CONFIG_DIR/packages.linux.alpine.txt"
    fi
    if [[ -f "$pkg_file" ]]; then
      local pkg_count
      pkg_count=$(grep -cv '^\s*#\|^\s*$' "$pkg_file" 2>/dev/null || echo 0)
      printf "  %-14s %d packages\n" "System" "$pkg_count"
    fi

    # Linux tools
    local tools_file="$CONFIG_DIR/tools.linux.bash"
    if [[ -f "$tools_file" ]]; then
      source "$tools_file"
      local tools_ok=0 tools_total=0 tools_missing=()
      for tool in "${LINUX_TOOL_ORDER[@]}"; do
        local var="TOOL_${tool}_check_cmd"
        local check_cmd="${!var}"
        local var2="TOOL_${tool}_alt_check_cmd"
        local alt="${!var2:-}"
        ((++tools_total))
        if command_exists "$check_cmd" || { [[ -n "$alt" ]] && command_exists "$alt"; }; then
          ((++tools_ok))
        else
          tools_missing+=("$tool")
        fi
      done
      printf "  %-14s %d / %d installed" "Tools" "$tools_ok" "$tools_total"
      if [[ ${#tools_missing[@]} -gt 0 ]]; then
        printf " (missing: %s)" "${tools_missing[*]}"
      fi
      echo
    fi
  fi

  # 2. NPM packages
  local npm_file="$CONFIG_DIR/packages.npm.txt"
  if [[ -f "$npm_file" ]]; then
    local npm_ok=0 npm_total=0 npm_missing=()
    local installed_npm=""
    if command_exists npm; then
      installed_npm=$(npm_global_packages)
    fi
    while IFS= read -r pkg; do
      ((++npm_total))
      local npm_name
      npm_name=$(npm_package_name "$pkg")
      if list_contains_line "$installed_npm" "$npm_name" ||
          grep -Fq -- "${npm_name}@" <<< "$installed_npm"; then
        ((++npm_ok))
      else
        npm_missing+=("$pkg")
      fi
    done < <(grep -v '^\s*#' "$npm_file" | grep -v '^\s*$')
    printf "  %-14s %d / %d installed" "NPM" "$npm_ok" "$npm_total"
    if [[ ${#npm_missing[@]} -gt 0 ]]; then
      printf " (missing: %s)" "${npm_missing[*]}"
    fi
    echo
  fi

  # 3. mise runtimes
  local mise_config="$DOTFILES_DIR/common/mise/.config/mise/config.toml"
  if [[ -f "$mise_config" ]]; then
    local mise_items=()
    while IFS='=' read -r tool version; do
      tool="${tool// /}"
      tool="${tool#\"}"
      tool="${tool%\"}"
      version="${version## }"
      version="${version%% }"
      version="${version//\"/}"
      [[ -z "$tool" ]] && continue
      mise_items+=("$tool"$'\t'"$version")
    done < <(awk '/^\[tools\]/{f=1;next} /^\[/{f=0} f && /=/' "$mise_config")
    printf "  %-14s " "mise"
    local first=true
    for item in "${mise_items[@]}"; do
      local t v
      IFS=$'\t' read -r t v <<< "$item"
      $first || printf ", "
      printf "%s (%s)" "$t" "$v"
      first=false
    done
    echo
  fi

  # 4. Other tools (not managed by package lists)
  local other_items=()
  command_exists dops && other_items+=("dops")
  command_exists op && other_items+=("op")
  if [[ "$os" == "linux" ]] && command_exists fc-list; then
    fc-list 2>/dev/null | grep -qi "UDEVGothic" && other_items+=("Nerd Font")
  fi
  if [[ ${#other_items[@]} -gt 0 ]]; then
    local other_str
    other_str=$(IFS=', '; echo "${other_items[*]}")
    printf "  %-14s %s\n" "Other" "$other_str"
  fi

  echo "────────────────────────────────────────────────────────"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
