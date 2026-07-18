// Pomodoro Timer CLI — scripts/pomodoro.sh の Rust 置換。
//
// 契約 (bash 版と完全互換):
//   - state dir: ${XDG_RUNTIME_DIR:-${TMPDIR:-$HOME/.cache}}/sketchybar/pomodoro
//   - state files: state / end_time / remaining / duration (各 1 行、末尾改行)
//     — sketchybar の表示 plugin がこれらを直接読むため形式変更不可
//   - 各操作後に `sketchybar --trigger pomodoro_update` (sketchybar 不在なら無視)
//   - stdout メッセージ・exit code も bash 版と一致させる

use std::env;
use std::fmt;
use std::fs;
use std::path::PathBuf;
use std::process::{Command, ExitCode, Stdio};
use std::str::FromStr;
use std::time::{SystemTime, UNIX_EPOCH};

const DEFAULT_DURATION: i64 = 1500; // 25分

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum State {
    Running,
    Paused,
    Stopped,
}

impl FromStr for State {
    type Err = ();
    fn from_str(s: &str) -> Result<Self, ()> {
        match s {
            "running" => Ok(State::Running),
            "paused" => Ok(State::Paused),
            _ => Ok(State::Stopped), // bash 版: 未知値・欠損は stopped 扱い
        }
    }
}

impl fmt::Display for State {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            State::Running => "running",
            State::Paused => "paused",
            State::Stopped => "stopped",
        })
    }
}

struct Store {
    dir: PathBuf,
}

impl Store {
    fn new() -> Store {
        let base = env::var("XDG_RUNTIME_DIR")
            .or_else(|_| env::var("TMPDIR"))
            .unwrap_or_else(|_| format!("{}/.cache", env::var("HOME").unwrap_or_default()));
        let dir = PathBuf::from(base).join("sketchybar/pomodoro");
        let _ = fs::create_dir_all(&dir);
        Store { dir }
    }

    fn read(&self, name: &str) -> Option<String> {
        fs::read_to_string(self.dir.join(name))
            .ok()
            .map(|s| s.trim().to_string())
    }

    fn read_i64(&self, name: &str) -> Option<i64> {
        self.read(name)?.parse().ok()
    }

    fn write(&self, name: &str, value: &str) {
        // bash の echo と同じく末尾改行付き
        let _ = fs::write(self.dir.join(name), format!("{value}\n"));
    }

    fn remove(&self, name: &str) {
        let _ = fs::remove_file(self.dir.join(name));
    }

    fn state(&self) -> State {
        self.read("state").unwrap_or_default().parse().unwrap()
    }

    fn duration(&self) -> i64 {
        self.read_i64("duration").unwrap_or(DEFAULT_DURATION)
    }

    fn remaining(&self) -> i64 {
        match self.state() {
            State::Running => {
                let end = self.read_i64("end_time").unwrap_or(0);
                end - now()
            }
            State::Paused => self.read_i64("remaining").unwrap_or_else(|| self.duration()),
            State::Stopped => self.duration(),
        }
    }
}

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn trigger_sketchybar() {
    let _ = Command::new("sketchybar")
        .args(["--trigger", "pomodoro_update"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

fn start(store: &Store, minutes: Option<i64>) {
    let mut duration = store.duration();
    if let Some(m) = minutes {
        duration = m * 60;
        store.write("duration", &duration.to_string());
    }

    let remaining = if store.state() == State::Paused {
        store.read_i64("remaining").unwrap_or(duration)
    } else {
        duration
    };

    store.write("end_time", &(now() + remaining).to_string());
    store.write("state", "running");
    trigger_sketchybar();
    println!("Started: {}m {}s", remaining / 60, remaining % 60);
}

fn pause(store: &Store) {
    if store.state() != State::Running {
        println!("Not running");
        return;
    }
    let remaining = store.read_i64("end_time").unwrap_or(0) - now();
    store.write("remaining", &remaining.to_string());
    store.write("state", "paused");
    trigger_sketchybar();
    println!("Paused: {}m {}s remaining", remaining / 60, remaining % 60);
}

fn toggle(store: &Store) {
    match store.state() {
        State::Running => pause(store),
        _ => start(store, None),
    }
}

fn reset(store: &Store) {
    let duration = store.duration();
    store.write("state", "stopped");
    store.write("remaining", &duration.to_string());
    store.remove("end_time");
    trigger_sketchybar();
    println!("Reset: {}m", duration / 60);
}

fn set_duration(store: &Store, minutes: i64) {
    let duration = minutes * 60;
    store.write("duration", &duration.to_string());
    if store.state() == State::Stopped {
        store.write("remaining", &duration.to_string());
    }
    trigger_sketchybar();
    println!("Duration set: {minutes}m");
}

fn status(store: &Store) {
    let remaining = store.remaining();
    println!("State: {}", store.state());
    println!("Duration: {}m", store.duration() / 60);
    println!("Remaining: {}m {}s", remaining / 60, remaining % 60);
}

fn parse_minutes(arg: Option<&str>) -> Result<Option<i64>, String> {
    match arg {
        None => Ok(None),
        Some(s) => s
            .parse()
            .map(Some)
            .map_err(|_| format!("invalid minutes: {s}")),
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    let store = Store::new();

    let cmd = args.first().map(String::as_str).unwrap_or("status");
    let arg1 = args.get(1).map(String::as_str);

    match cmd {
        "start" => match parse_minutes(arg1) {
            Ok(m) => start(&store, m),
            Err(e) => {
                eprintln!("{e}");
                return ExitCode::FAILURE;
            }
        },
        "pause" => pause(&store),
        "toggle" => toggle(&store),
        "reset" => reset(&store),
        "set" => match parse_minutes(arg1) {
            Ok(m) => set_duration(&store, m.unwrap_or(25)),
            Err(e) => {
                eprintln!("{e}");
                return ExitCode::FAILURE;
            }
        },
        "status" => status(&store),
        _ => {
            println!("Usage: pomodoro <start|pause|toggle|reset|set|status> [minutes]");
            return ExitCode::FAILURE;
        }
    }
    ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn state_roundtrip() {
        for (s, e) in [
            ("running", State::Running),
            ("paused", State::Paused),
            ("stopped", State::Stopped),
            ("garbage", State::Stopped),
            ("", State::Stopped),
        ] {
            assert_eq!(s.parse::<State>().unwrap(), e);
        }
        assert_eq!(State::Running.to_string(), "running");
    }

    #[test]
    fn negative_remaining_formats_like_bash() {
        // bash: $((-42 / 60)) = 0, $((-42 % 60)) = -42 (trunc toward zero)
        let r: i64 = -42;
        assert_eq!(format!("{}m {}s", r / 60, r % 60), "0m -42s");
    }
}
