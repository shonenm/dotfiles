// tmux window 操作 — $TMUX 無しでは window 作成を skip する (bash と同じ)。

use std::process::{Command, Stdio};

pub fn in_tmux() -> bool {
    std::env::var("TMUX").map(|v| !v.is_empty()).unwrap_or(false)
}

pub fn window_exists(name: &str) -> bool {
    let Ok(out) = Command::new("tmux")
        .args(["list-windows", "-F", "#{window_name}"])
        .output()
    else {
        return false;
    };
    if !out.status.success() {
        return false;
    }
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .any(|l| l == name)
}

pub fn new_window(name: &str, cwd: &str) {
    let _ = Command::new("tmux")
        .args(["new-window", "-n", name, "-c", cwd])
        .status();
}

pub fn kill_window(name: &str) {
    let _ = Command::new("tmux")
        .args(["kill-window", "-t", name])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

pub fn select_window(name: &str) {
    let _ = Command::new("tmux").args(["select-window", "-t", name]).status();
}
