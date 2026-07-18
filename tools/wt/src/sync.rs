// ignored ファイル同期 — main worktree の gitignore 対象を新 worktree へ。
// 分類: skip (再生成可能キャッシュ) / symlink (大きく安全に共有可) / copy (それ以外)。
// 設定は main worktree 直下の .wt-config (TOML)。未配置なら組込みデフォルト。

use crate::log;
use serde::Deserialize;
use std::path::Path;
use std::process::Command;

#[derive(Debug, Deserialize)]
struct Config {
    #[serde(default)]
    symlink_dirs: Vec<String>,
    #[serde(default)]
    skip_dirs: Vec<String>,
}

fn default_symlink_dirs() -> Vec<String> {
    [
        "node_modules",
        ".pnpm-store",
        ".venv",
        "agents/worker/.venv",
        "agents/api/.venv",
        "bff/node_modules",
        "web/node_modules",
        "hocuspocus/node_modules",
        "test-e2e/node_modules",
        "packages/*/node_modules",
        "seeding/node_modules",
    ]
    .iter()
    .map(|s| s.to_string())
    .collect()
}

fn default_skip_dirs() -> Vec<String> {
    [
        ".mypy_cache",
        ".turbo",
        ".serena/cache",
        ".dumps",
        ".ruff_cache",
        ".pytest_cache",
        "anonymizer/output",
        "agents/.mypy_cache",
        "__pycache__",
    ]
    .iter()
    .map(|s| s.to_string())
    .collect()
}

fn load_config(src: &str) -> (Vec<String>, Vec<String>) {
    let path = Path::new(src).join(".wt-config");
    if let Ok(body) = std::fs::read_to_string(&path)
        && let Ok(cfg) = toml::from_str::<Config>(&body)
    {
        let sym = if cfg.symlink_dirs.is_empty() {
            default_symlink_dirs()
        } else {
            cfg.symlink_dirs
        };
        let skip = if cfg.skip_dirs.is_empty() {
            default_skip_dirs()
        } else {
            cfg.skip_dirs
        };
        return (sym, skip);
    }
    (default_symlink_dirs(), default_skip_dirs())
}

/// glob マッチ ('*' は '/' を含む任意列にマッチ = bash `[[ str == pat ]]` と同じ)。
fn glob_match(pat: &str, s: &str) -> bool {
    // '*' で分割し、各リテラル片が順に現れるか (先頭/末尾は固定)。
    let parts: Vec<&str> = pat.split('*').collect();
    if parts.len() == 1 {
        return pat == s; // '*' 無し = 完全一致
    }
    let mut pos = 0;
    // 先頭片は prefix 固定
    if !s[pos..].starts_with(parts[0]) {
        return false;
    }
    pos += parts[0].len();
    // 中間片は順に出現
    for part in &parts[1..parts.len() - 1] {
        if part.is_empty() {
            continue;
        }
        match s[pos..].find(part) {
            Some(i) => pos += i + part.len(),
            None => return false,
        }
    }
    // 末尾片は suffix 固定
    let last = parts[parts.len() - 1];
    s[pos..].ends_with(last) && s.len() - pos >= last.len()
}

pub fn copy_ignored(src: &str, dst: &str) {
    let (symlink_dirs, skip_dirs) = load_config(src);

    let out = Command::new("git")
        .args([
            "-C",
            src,
            "ls-files",
            "--others",
            "--ignored",
            "--exclude-standard",
            "--directory",
            "--no-empty-directory",
        ])
        .output();
    let Ok(out) = out else { return };
    if !out.status.success() {
        return;
    }
    let entries = String::from_utf8_lossy(&out.stdout);
    let entries: Vec<&str> = entries.lines().filter(|l| !l.is_empty()).collect();
    if entries.is_empty() {
        return;
    }

    log::info("Syncing ignored files from main worktree...");
    for entry in entries {
        let src_path = format!("{src}/{entry}");
        let dst_path = format!("{dst}/{entry}");
        if !Path::new(&src_path).exists() {
            continue;
        }
        let clean = entry.strip_suffix('/').unwrap_or(entry);

        // skip: 部分一致
        if skip_dirs.iter().any(|p| clean.contains(p.as_str())) {
            continue;
        }
        // symlink: glob 一致
        if symlink_dirs.iter().any(|p| glob_match(p, clean)) {
            let abs_src = std::fs::canonicalize(src)
                .map(|p| p.join(clean).to_string_lossy().to_string())
                .unwrap_or_else(|_| format!("{src}/{clean}"));
            let dst_clean = dst_path.strip_suffix('/').unwrap_or(&dst_path);
            if let Some(parent) = Path::new(dst_clean).parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            let _ = Command::new("ln")
                .args(["-snf", &abs_src, dst_clean])
                .status();
            continue;
        }
        // copy: CoW を優先
        if let Some(parent) = Path::new(&dst_path).parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        copy_recursive(&src_path, &dst_path);
    }
    log::success("Synced ignored files");
}

fn copy_recursive(src: &str, dst: &str) {
    let ok = if cfg!(target_os = "macos") {
        // APFS clonefile (CoW)。失敗時は通常コピー。
        try_cp(&["-ac", src, dst]) || try_cp(&["-a", src, dst])
    } else {
        try_cp(&["-ax", "--reflink=auto", src, dst]) || try_cp(&["-ax", src, dst])
    };
    let _ = ok;
}

fn try_cp(args: &[&str]) -> bool {
    Command::new("cp")
        .args(args)
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn glob_exact_and_star() {
        assert!(glob_match("node_modules", "node_modules"));
        assert!(!glob_match("node_modules", "node_modules2"));
        assert!(glob_match("packages/*/node_modules", "packages/a/node_modules"));
        assert!(glob_match("packages/*/node_modules", "packages/a/b/node_modules")); // * は / も跨ぐ
        assert!(!glob_match("packages/*/node_modules", "packages/a/node_modules_x"));
        assert!(!glob_match("packages/*/node_modules", "other/a/node_modules"));
    }

    #[test]
    fn skip_is_substring() {
        let skip = default_skip_dirs();
        assert!(skip.iter().any(|p| "src/__pycache__".contains(p.as_str())));
        assert!(skip.iter().any(|p| ".pytest_cache".contains(p.as_str())));
        assert!(!skip.iter().any(|p| "node_modules".contains(p.as_str())));
    }
}
