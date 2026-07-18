// git worktree 操作 — Phase 0-6 の porcelain parser を型付きで再現。
// worktree の add/remove は git CLI が正なので shell-out (git2 crate は使わない)。

use std::path::Path;
use std::process::{Command, Output};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Worktree {
    pub path: String,
    pub branch: Option<String>, // detached は None
}

fn git(args: &[&str]) -> std::io::Result<Output> {
    Command::new("git").args(args).output()
}

/// stdout をトリムして返す (失敗時 None)。
fn git_stdout(args: &[&str]) -> Option<String> {
    let out = git(args).ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

/// git リポジトリ内か。
pub fn check_repo() -> bool {
    git(&["rev-parse", "--git-dir"])
        .map(|o| o.status.success())
        .unwrap_or(false)
}

/// `git worktree list --porcelain` を構造化。
pub fn list() -> Vec<Worktree> {
    match git_stdout(&["worktree", "list", "--porcelain"]) {
        Some(out) => parse_porcelain(&out),
        None => Vec::new(),
    }
}

/// porcelain 出力のパース (純粋関数)。各レコードは "worktree <path>" で始まり
/// "branch refs/heads/<name>" を持つ (detached は branch 無し)。
pub fn parse_porcelain(out: &str) -> Vec<Worktree> {
    let mut result = Vec::new();
    let mut path: Option<String> = None;
    let mut branch: Option<String> = None;
    for line in out.lines() {
        if let Some(p) = line.strip_prefix("worktree ") {
            if let Some(prev) = path.take() {
                result.push(Worktree { path: prev, branch: branch.take() });
            }
            path = Some(p.to_string());
            branch = None;
        } else if let Some(b) = line.strip_prefix("branch ") {
            branch = Some(b.strip_prefix("refs/heads/").unwrap_or(b).to_string());
        }
    }
    if let Some(p) = path {
        result.push(Worktree { path: p, branch });
    }
    result
}

/// メイン (最初の) worktree のパス。
pub fn main_worktree() -> Option<String> {
    list().into_iter().next().map(|w| w.path)
}

/// メイン worktree の basename。
pub fn repo_name() -> Option<String> {
    let m = main_worktree()?;
    Path::new(&m)
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
}

/// origin/HEAD → main → master の順でデフォルトブランチを検出。
pub fn default_branch() -> Option<String> {
    if let Some(r) = git_stdout(&["symbolic-ref", "refs/remotes/origin/HEAD"]) {
        return Some(r.trim_start_matches("refs/remotes/origin/").to_string());
    }
    for cand in ["main", "master"] {
        let refname = format!("refs/remotes/origin/{cand}");
        if git(&["show-ref", "--verify", "--quiet", &refname])
            .map(|o| o.status.success())
            .unwrap_or(false)
        {
            return Some(cand.to_string());
        }
    }
    None
}

/// `${main}--wt--${branch//\//-}`
pub fn worktree_path(branch: &str) -> Option<String> {
    let main = main_worktree()?;
    Some(format!("{main}--wt--{}", branch.replace('/', "-")))
}

/// `${repo}#${branch}`
pub fn window_name(branch: &str) -> Option<String> {
    Some(format!("{}#{branch}", repo_name()?))
}

/// 指定 branch の worktree が存在するか (パス完全一致)。
pub fn exists(branch: &str) -> bool {
    let Some(path) = worktree_path(branch) else {
        return false;
    };
    list().iter().any(|w| w.path == path)
}

pub fn local_branch_exists(branch: &str) -> bool {
    git(&["show-ref", "--verify", "--quiet", &format!("refs/heads/{branch}")])
        .map(|o| o.status.success())
        .unwrap_or(false)
}

pub fn remote_branch_exists(branch: &str) -> bool {
    git(&[
        "show-ref",
        "--verify",
        "--quiet",
        &format!("refs/remotes/origin/{branch}"),
    ])
    .map(|o| o.status.success())
    .unwrap_or(false)
}

/// git 出力を stderr に流しつつ実行 (bash が `>&2` していたのと同じ)。
/// 子の stdout を親の stderr fd に複製して繋ぐ。
pub fn run_inherit(args: &[&str]) -> bool {
    use std::os::fd::AsFd;
    let stderr_dup = std::io::stderr()
        .as_fd()
        .try_clone_to_owned()
        .map(std::process::Stdio::from);
    let mut cmd = Command::new("git");
    cmd.args(args);
    if let Ok(s) = stderr_dup {
        cmd.stdout(s);
    }
    cmd.status().map(|s| s.success()).unwrap_or(false)
}

pub fn fetch(remote: &str, branch: &str) -> bool {
    run_inherit(&["fetch", remote, branch])
}

pub fn worktree_add(path: &str, branch: &str) -> bool {
    run_inherit(&["worktree", "add", path, branch])
}

pub fn worktree_add_new_branch(branch: &str, path: &str, base: &str) -> bool {
    run_inherit(&["worktree", "add", "-b", branch, path, base])
}

/// clean 用: git のエラーを抑制 (bash は `2>/dev/null`)。
pub fn worktree_remove(path: &str) -> bool {
    git(&["worktree", "remove", path])
        .map(|o| o.status.success())
        .unwrap_or(false)
}

/// delete 用: git の fatal を stderr に見せる (bash wt_delete は抑制しない)。
pub fn worktree_remove_verbose(path: &str) -> bool {
    Command::new("git")
        .args(["worktree", "remove", path])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

pub fn worktree_prune() {
    let _ = git(&["worktree", "prune"]);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_porcelain_records() {
        let out = "worktree /repo\nHEAD abc\nbranch refs/heads/main\n\n\
                   worktree /repo--wt--feat-login\nHEAD def\nbranch refs/heads/feat/login\n\n\
                   worktree /repo--wt--detached\nHEAD 999\ndetached\n";
        let wts = parse_porcelain(out);
        assert_eq!(wts.len(), 3);
        assert_eq!(wts[0], Worktree { path: "/repo".into(), branch: Some("main".into()) });
        assert_eq!(wts[1].branch, Some("feat/login".into())); // slash 保持
        assert_eq!(wts[2].branch, None); // detached
    }

    #[test]
    fn slug_replaces_slashes() {
        assert_eq!("feat/login/x".replace('/', "-"), "feat-login-x");
    }
}
