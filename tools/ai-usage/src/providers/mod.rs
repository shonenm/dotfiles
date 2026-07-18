// Provider 抽象 — 4 プロバイダ共通の「token → fetch → parse → 2 window」の型。
// 各 provider は cache 行の serialize/deserialize を bash 互換で実装する。

pub mod claude;
pub mod cursor;
pub mod gemini;

use std::path::PathBuf;

/// reset 時刻の表現。cache にはこの生値を保存し、render 時に現在時刻から残りを計算。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Reset {
    None,
    Iso(String),
    #[allow(dead_code)] // codex/cursor (M2/M3) で使用
    Unix(i64),
}

impl Reset {
    /// cache 用の文字列（空 = None）。
    pub fn to_field(&self) -> String {
        match self {
            Reset::None => String::new(),
            Reset::Iso(s) => s.clone(),
            Reset::Unix(n) => n.to_string(),
        }
    }
}

/// 2 window ぶんの使用率と reset。label は provider 定数。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Usage {
    pub a_pct: i64,
    pub a_reset: Reset,
    pub b_pct: i64,
    pub b_reset: Reset,
}

/// 0-100 にクランプ（bash の max(0,min(100,...)) 相当）。
pub fn clamp_pct(v: i64) -> i64 {
    v.clamp(0, 100)
}

pub trait Provider {
    fn icon(&self) -> &'static str;
    /// (a_label, b_label) 例: ("current", "weekly") / ("total", "auto")
    fn labels(&self) -> (&'static str, &'static str);
    fn cache_path(&self) -> PathBuf;
    fn cache_ttl(&self) -> u64 {
        300
    }
    fn fail_ttl(&self) -> u64 {
        60
    }
    /// 新規取得。Err は「fail backoff + placeholder」を意味する（bash の touch FAIL + na）。
    fn fetch(&self) -> anyhow::Result<Usage>;
    /// Usage → cache 1 行（bash 互換フォーマット）。
    fn to_cache(&self, u: &Usage) -> String;
    /// cache 1 行 → Usage（バージョン不一致・壊れは None）。
    #[allow(clippy::wrong_self_convention)] // provider dispatch のため &self が必要
    fn from_cache(&self, line: &str) -> Option<Usage>;
}

/// "{a}|{b}|{r1_iso}|{r2_iso}" 形式の cache 行をパース（claude / gemini 共通）。
pub fn parse_two_iso_cache(line: &str) -> Option<Usage> {
    let f: Vec<&str> = line.split('|').collect();
    let a_pct: i64 = f.first()?.parse().ok()?;
    let b_pct: i64 = f.get(1)?.parse().ok()?;
    let iso = |i: usize| match f.get(i) {
        Some(s) if !s.is_empty() => Reset::Iso((*s).to_string()),
        _ => Reset::None,
    };
    Some(Usage {
        a_pct,
        a_reset: iso(2),
        b_pct,
        b_reset: iso(3),
    })
}

/// {XDG_CACHE_HOME:-~/.cache}/tmux/<name>
pub fn tmux_cache_path(name: &str) -> PathBuf {
    let base = std::env::var("XDG_CACHE_HOME").unwrap_or_else(|_| {
        format!("{}/.cache", std::env::var("HOME").unwrap_or_default())
    });
    PathBuf::from(base).join("tmux").join(name)
}
