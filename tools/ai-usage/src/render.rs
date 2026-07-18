// 出力レコード生成 — bash 版の python render() と bit 単位で一致させる。
//   成功: "ICON\x1fLABEL\x1fGAUGE\x1fPCT%\x1fREMAINING" を 2 行
//   データ無し: "ICON\x1f--" を 1 行

use crate::providers::Reset;
use std::time::{SystemTime, UNIX_EPOCH};

const US: char = '\u{1f}';
const BARS: [char; 9] = [' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];

/// 使用率 0-100 を 9 段階ゲージ 1 文字へ。0%=空白、低%でも最低 ▁（bash と同じ）。
pub fn bar(v: i64) -> char {
    if v <= 0 {
        return BARS[0];
    }
    if v >= 100 {
        return BARS[8];
    }
    BARS[(1).max((v * 8 / 100) as usize)]
}

fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// reset 時刻までの残りを "0m" / "{m}m" / "{h}h{mm}m" / "{d}d{h}h" 形式へ。
/// reset 無し・parse 失敗は空文字（bash の except 分岐と同じ）。
pub fn humanize(reset: &Reset) -> String {
    let target = match reset {
        Reset::None => return String::new(),
        Reset::Iso(s) => match s.parse::<jiff::Timestamp>() {
            Ok(ts) => ts.as_second(),
            Err(_) => return String::new(),
        },
        Reset::Unix(secs) => *secs,
    };
    humanize_delta(target - now_secs())
}

fn humanize_delta(delta: i64) -> String {
    if delta <= 0 {
        return "0m".to_string();
    }
    let total_min = delta / 60;
    let (h, m) = (total_min / 60, total_min % 60);
    if h >= 24 {
        let (d, h) = (h / 24, h % 24);
        return format!("{d}d{h}h");
    }
    if h > 0 {
        format!("{h}h{m:02}m")
    } else {
        format!("{m}m")
    }
}

/// データ無し 1 行。
pub fn na_line(icon: &str) -> String {
    format!("{icon}{US}--")
}

/// 成功時の 1 レコード。
pub fn record(icon: &str, label: &str, pct: i64, reset: &Reset) -> String {
    format!(
        "{icon}{US}{label}{US}{gauge}{US}{pct}%{US}{rem}",
        gauge = bar(pct),
        rem = humanize(reset),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bar_boundaries() {
        assert_eq!(bar(0), ' ');
        assert_eq!(bar(-5), ' ');
        assert_eq!(bar(1), '▁'); // 1*8/100=0 → max(1,0)=1
        assert_eq!(bar(50), BARS[4]); // 50*8/100=4
        assert_eq!(bar(100), '█');
        assert_eq!(bar(150), '█');
        assert_eq!(bar(99), BARS[7]); // 99*8/100=7
    }

    #[test]
    fn humanize_delta_formats() {
        assert_eq!(humanize_delta(-10), "0m");
        assert_eq!(humanize_delta(0), "0m");
        assert_eq!(humanize_delta(59), "0m");
        assert_eq!(humanize_delta(60), "1m");
        assert_eq!(humanize_delta(90 * 60), "1h30m");
        assert_eq!(humanize_delta(5 * 60), "5m");
        assert_eq!(humanize_delta(25 * 3600), "1d1h");
        assert_eq!(humanize_delta(3 * 3600 + 5 * 60), "3h05m");
    }

    #[test]
    fn record_format() {
        let r = record("X", "current", 42, &Reset::None);
        assert_eq!(r, "X\u{1f}current\u{1f}▃\u{1f}42%\u{1f}"); // 42*8/100=3
    }
}
