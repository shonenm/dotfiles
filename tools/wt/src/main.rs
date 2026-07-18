// wt — git worktree + tmux window 統合管理 CLI (scripts/wt + wt-lib.sh の置換)。
//
// user-facing:
//   wt new <branch> [base]     worktree + tmux window 作成
//   wt checkout <pr-number>    PR を worktree に checkout
//   wt list                    worktree 一覧
//   wt delete <branch>         worktree + window 削除
//   wt clean                   --wt-- worktree を全削除
// plumbing (ralph が使用):
//   wt path <branch>           worktree パスを print
//   wt exists <branch>         存在すれば exit 0
//   wt root                    メイン worktree パス (git repo 外なら exit 1)
//   wt window-name <branch>    tmux window 名を print
//   wt sync-ignored <src> <dst>  ignored ファイル同期

mod git;
mod log;
mod sync;
mod tmux;

use std::process::ExitCode;

fn require_repo() -> Result<(), ExitCode> {
    if git::check_repo() {
        Ok(())
    } else {
        log::error("Not in a git repository");
        Err(ExitCode::FAILURE)
    }
}

/// worktree を作成し、tmux window を用意。stdout に worktree パスを print。
fn cmd_new(branch: &str, base: Option<&str>) -> ExitCode {
    if branch.is_empty() {
        log::error("Usage: wt new <branch> [base]");
        return ExitCode::FAILURE;
    }
    let Some(path) = git::worktree_path(branch) else {
        log::error("could not resolve worktree path");
        return ExitCode::FAILURE;
    };
    let Some(win) = git::window_name(branch) else {
        log::error("could not resolve window name");
        return ExitCode::FAILURE;
    };

    let found = git::exists(branch);

    // 既存 worktree + 既存 window → 切替
    if found && tmux::window_exists(&win) {
        log::info(&format!("Switching to existing window: {win}"));
        tmux::select_window(&win);
        println!("{path}");
        return ExitCode::SUCCESS;
    }
    // 孤立 window (worktree 無し) → kill
    if !found && tmux::window_exists(&win) {
        tmux::kill_window(&win);
        log::info(&format!("Killed orphaned window: {win}"));
    }

    // worktree 作成
    if !found {
        let ok = if git::local_branch_exists(branch) || git::remote_branch_exists(branch) {
            git::worktree_add(&path, branch)
        } else {
            let base = match base {
                Some(b) if !b.is_empty() => b.to_string(),
                _ => {
                    let Some(def) = git::default_branch() else {
                        log::error("Could not detect default branch");
                        return ExitCode::FAILURE;
                    };
                    git::fetch("origin", &def);
                    let b = format!("origin/{def}");
                    log::info(&format!("Base: {b} (default branch)"));
                    b
                }
            };
            git::worktree_add_new_branch(branch, &path, &base)
        };
        if !ok {
            log::error("git worktree add failed");
            return ExitCode::FAILURE;
        }
        if let Some(main) = git::main_worktree() {
            sync::copy_ignored(&main, &path);
        }
    }

    // tmux window
    if tmux::in_tmux() {
        tmux::new_window(&win, &path);
        log::success(&format!("Created window: {win}"));
    } else {
        log::info(&format!("Worktree ready: {path}"));
        log::info("Not in tmux session, skipping window creation");
    }

    println!("{path}");
    ExitCode::SUCCESS
}

fn cmd_checkout(pr: &str) -> ExitCode {
    if pr.is_empty() {
        log::error("Usage: wt checkout <pr-number>");
        return ExitCode::FAILURE;
    }
    let out = std::process::Command::new("gh")
        .args(["pr", "view", pr, "--json", "headRefName,baseRefName"])
        .output();
    let Ok(out) = out else {
        log::error("gh CLI is not installed");
        return ExitCode::FAILURE;
    };
    if !out.status.success() {
        log::error(&format!("Failed to get PR #{pr}"));
        return ExitCode::FAILURE;
    }
    let v: serde_json::Value = match serde_json::from_slice(&out.stdout) {
        Ok(v) => v,
        Err(_) => {
            log::error("failed to parse gh output");
            return ExitCode::FAILURE;
        }
    };
    let branch = v["headRefName"].as_str().unwrap_or("");
    let base = v["baseRefName"].as_str().unwrap_or("");
    log::info(&format!("PR #{pr}: {branch} (base: {base})"));
    git::fetch("origin", branch);
    cmd_new(branch, None)
}

fn cmd_list() -> ExitCode {
    let Some(repo) = git::repo_name() else {
        log::error("could not resolve repo");
        return ExitCode::FAILURE;
    };
    let mut found = false;
    for wt in git::list() {
        if !wt.path.contains("--wt--") {
            continue;
        }
        found = true;
        let branch = wt.branch.unwrap_or_default();
        let win = format!("{repo}#{branch}");
        let status = if tmux::window_exists(&win) { "[tmux]" } else { "" };
        println!("  {branch:<40} {:<20} {status}", wt.path);
    }
    if !found {
        log::info("No worktrees found");
    }
    ExitCode::SUCCESS
}

fn cmd_delete(branch: &str) -> ExitCode {
    if branch.is_empty() {
        log::error("Usage: wt delete <branch>");
        return ExitCode::FAILURE;
    }
    let (Some(path), Some(win)) = (git::worktree_path(branch), git::window_name(branch)) else {
        log::error("could not resolve worktree");
        return ExitCode::FAILURE;
    };
    if tmux::window_exists(&win) {
        tmux::kill_window(&win);
        log::info(&format!("Closed window: {win}"));
    }
    if git::exists(branch) {
        if !git::worktree_remove_verbose(&path) {
            log::error("Failed to remove worktree (uncommitted changes?)");
            return ExitCode::FAILURE;
        }
        log::success(&format!("Removed worktree: {path}"));
    } else {
        log::info(&format!("Worktree not found: {path}"));
    }
    ExitCode::SUCCESS
}

fn cmd_clean() -> ExitCode {
    let Some(repo) = git::repo_name() else {
        log::error("could not resolve repo");
        return ExitCode::FAILURE;
    };
    let mut found = false;
    for wt in git::list() {
        if !wt.path.contains("--wt--") {
            continue;
        }
        found = true;
        let branch = wt.branch.unwrap_or_default();
        let win = format!("{repo}#{branch}");
        if tmux::window_exists(&win) {
            tmux::kill_window(&win);
            log::info(&format!("Closed window: {win}"));
        }
        if git::worktree_remove(&wt.path) {
            log::success(&format!("Removed: {}", wt.path));
        } else {
            log::error(&format!(
                "Failed to remove: {} (uncommitted changes?)",
                wt.path
            ));
        }
    }
    git::worktree_prune();
    if found {
        log::success("Worktree prune complete");
    } else {
        log::info("No worktrees to clean");
    }
    ExitCode::SUCCESS
}

const HELP: &str = "wt - git worktree + tmux window manager

Usage:
  wt new <branch> [base]     Create worktree + tmux window
  wt checkout <pr-number>    Checkout PR into worktree
  wt list                    List worktrees
  wt delete <branch>         Remove worktree + tmux window
  wt clean                   Remove all worktrees";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let cmd = args.first().map(String::as_str).unwrap_or("help");
    let a1 = args.get(1).map(String::as_str);
    let a2 = args.get(2).map(String::as_str);

    let needs_repo = matches!(
        cmd,
        "new" | "checkout"
            | "list"
            | "delete"
            | "clean"
            | "path"
            | "exists"
            | "root"
            | "window-name"
            | "sync-ignored"
    );
    if needs_repo && require_repo().is_err() {
        return ExitCode::FAILURE;
    }

    match cmd {
        "new" => cmd_new(a1.unwrap_or(""), a2),
        "checkout" => cmd_checkout(a1.unwrap_or("")),
        "list" => cmd_list(),
        "delete" => cmd_delete(a1.unwrap_or("")),
        "clean" => cmd_clean(),

        // plumbing (ralph)
        "path" => match git::worktree_path(a1.unwrap_or("")) {
            Some(p) => {
                println!("{p}");
                ExitCode::SUCCESS
            }
            None => ExitCode::FAILURE,
        },
        "exists" => {
            if git::exists(a1.unwrap_or("")) {
                ExitCode::SUCCESS
            } else {
                ExitCode::FAILURE
            }
        }
        "root" => match git::main_worktree() {
            Some(p) => {
                println!("{p}");
                ExitCode::SUCCESS
            }
            None => ExitCode::FAILURE,
        },
        "window-name" => match git::window_name(a1.unwrap_or("")) {
            Some(n) => {
                println!("{n}");
                ExitCode::SUCCESS
            }
            None => ExitCode::FAILURE,
        },
        "sync-ignored" => {
            let (Some(s), Some(d)) = (a1, a2) else {
                log::error("Usage: wt sync-ignored <src> <dst>");
                return ExitCode::FAILURE;
            };
            sync::copy_ignored(s, d);
            ExitCode::SUCCESS
        }

        _ => {
            println!("{HELP}");
            ExitCode::SUCCESS
        }
    }
}
