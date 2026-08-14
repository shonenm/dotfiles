// Cursor usage — token ladder (env → mac Keychain → linux secret-service →
// Cursor IDE state.vscdb) で取得した token で api2.cursor.sh を叩く。
// sqlite fallback は sqlite3 CLI へ shell-out (keychain/secret-tool と同じ方針、
// rusqlite の重い build 依存を避ける)。

use super::{Provider, Reset, Usage, clamp_pct, tmux_cache_path};
use crate::http;
use anyhow::{Context, Result, anyhow};
use serde_json::Value;
use std::path::PathBuf;
use std::process::Command;

pub struct Cursor;

fn env_nonempty(key: &str) -> Option<String> {
    std::env::var(key).ok().filter(|s| !s.is_empty())
}

impl Cursor {
    fn token(&self) -> Result<String> {
        if let Some(t) = env_nonempty("CURSOR_AUTH_TOKEN").or_else(|| env_nonempty("CURSOR_API_KEY"))
        {
            return Ok(t);
        }

        #[cfg(target_os = "macos")]
        if let Ok(out) = Command::new("security")
            .args([
                "find-generic-password",
                "-s",
                "cursor-access-token",
                "-a",
                "cursor-user",
                "-w",
            ])
            .output()
            && out.status.success()
        {
            let t = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !t.is_empty() {
                return Ok(t);
            }
        }

        #[cfg(not(target_os = "macos"))]
        if let Ok(out) = Command::new("secret-tool")
            .args([
                "lookup",
                "service",
                "cursor-access-token",
                "account",
                "cursor-user",
            ])
            .output()
            && out.status.success()
        {
            let t = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !t.is_empty() {
                return Ok(t);
            }
        }

        if let Some(t) = self.token_from_sqlite() {
            return Ok(t);
        }
        Err(anyhow!("no cursor token"))
    }

    fn token_from_sqlite(&self) -> Option<String> {
        let home = std::env::var("HOME").unwrap_or_default();
        let config = std::env::var("XDG_CONFIG_HOME").unwrap_or_else(|_| format!("{home}/.config"));
        let dbs = [
            format!("{home}/Library/Application Support/Cursor/User/globalStorage/state.vscdb"),
            format!("{config}/Cursor/User/globalStorage/state.vscdb"),
        ];
        let keys = [
            "cursorAuth/accessToken",
            "cursor.accessToken",
            "workos.sessionToken",
            "cursorAuth/refreshToken",
        ];
        for db in &dbs {
            if !std::path::Path::new(db).exists() {
                continue;
            }
            for key in keys {
                let Ok(out) = Command::new("sqlite3")
                    .arg(format!("file:{db}?mode=ro"))
                    .arg(format!(
                        "SELECT value FROM ItemTable WHERE key = '{key}' LIMIT 1"
                    ))
                    .output()
                else {
                    continue;
                };
                if !out.status.success() {
                    continue;
                }
                let raw = String::from_utf8_lossy(&out.stdout).trim().to_string();
                if raw.is_empty() {
                    continue;
                }
                if let Some(t) = extract_token(&raw) {
                    return Some(t);
                }
            }
        }
        None
    }
}

/// state.vscdb の value (JSON dict / JSON string / 生文字列) から token を取り出す。
fn extract_token(raw: &str) -> Option<String> {
    if let Ok(v) = serde_json::from_str::<Value>(raw) {
        if let Some(obj) = v.as_object() {
            for k in ["accessToken", "token"] {
                if let Some(s) = obj.get(k).and_then(Value::as_str)
                    && !s.is_empty()
                {
                    return Some(s.to_string());
                }
            }
            return None;
        }
        if let Some(s) = v.as_str()
            && !s.is_empty()
        {
            return Some(s.to_string());
        }
    }
    Some(raw.to_string()) // JSON でなければ生値
}

impl Provider for Cursor {
    fn icon(&self) -> &'static str {
        "\u{25c6}" // ◆
    }

    fn labels(&self) -> (&'static str, &'static str) {
        ("cursor", "other")
    }

    fn cache_path(&self) -> PathBuf {
        tmux_cache_path("cursor_usage")
    }

    fn fetch(&self) -> Result<Usage> {
        let token = self.token()?;
        let base = std::env::var("CURSOR_API_BASE")
            .unwrap_or_else(|_| "https://api2.cursor.sh".to_string());

        // 主: Connect protocol の DashboardService
        let raw = http::agent()
            .post(format!(
                "{base}/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
            ))
            .header("Authorization", &format!("Bearer {token}"))
            .header("Content-Type", "application/json")
            .header("Connect-Protocol-Version", "1")
            .send(b"{}")
            .ok()
            .and_then(|mut r| r.body_mut().read_to_string().ok())
            .filter(|s| !s.is_empty());

        // 副: /auth/usage フォールバック
        let raw = match raw {
            Some(r) => r,
            None => http::agent()
                .get(format!("{base}/auth/usage"))
                .header("Authorization", &format!("Bearer {token}"))
                .call()
                .context("usage fallback request")?
                .body_mut()
                .read_to_string()
                .context("reading fallback body")?,
        };

        let v: Value = serde_json::from_str(&raw).context("parsing usage json")?;
        parse_usage(&v).ok_or_else(|| anyhow!("no usable usage"))
    }

    fn to_cache(&self, u: &Usage) -> String {
        // "{cursor}|{other}|{billing_end}" — reset は両 window 共有、a_reset を正とする
        format!("{}|{}|{}", u.a_pct, u.b_pct, u.a_reset.to_field())
    }

    fn from_cache(&self, line: &str) -> Option<Usage> {
        let f: Vec<&str> = line.split('|').collect();
        let a_pct: i64 = f.first()?.parse().ok()?;
        let b_pct: i64 = f.get(1)?.parse().ok()?;
        let reset = match f.get(2) {
            Some(s) if !s.is_empty() => parse_reset(s),
            _ => Reset::None,
        };
        Some(Usage {
            a_pct,
            a_reset: reset.clone(),
            b_pct,
            b_reset: reset,
        })
    }
}

/// billingCycleEnd は ISO or unix(ms/s)。数値なら ms を s に正規化 (bash の >10^10 判定)。
fn parse_reset(s: &str) -> Reset {
    if let Ok(n) = s.parse::<i64>() {
        let secs = if n > 10_000_000_000 { n / 1000 } else { n };
        Reset::Unix(secs)
    } else {
        Reset::Iso(s.to_string())
    }
}

/// 生の割合を整数 % へ。0 でない消費が 0% に丸められると「未使用」に見えるため 1% を
/// 下限にする (Cursor ダッシュボードと同じ挙動: 0.42% → 1%)。
fn round_pct(v: f64) -> i64 {
    if v <= 0.0 {
        0
    } else {
        (v.round() as i64).max(1)
    }
}

fn parse_usage(v: &Value) -> Option<Usage> {
    let pu = &v["planUsage"];
    if pu.is_object() && !pu.as_object().unwrap().is_empty() {
        // Pro+ 以降、枠は 2 プールに分かれる:
        //   Cursor Models (Composer/Grok/Vega) = autoPercentUsed
        //   Other Models  (Claude/GPT/Gemini)  = apiPercentUsed ($70 の API 枠)
        // 旧 includedSpend/limit は単一プール時代の名残で、分子が両プール合計の消費額・
        // 分母が Other Models だけの $70 と噛み合わず、実消費 4%/1% が 48% に化ける。
        // 使用を止めるゲートはプールごとの割合なので、そちらを直接読む。
        let s = round_pct(pu["autoPercentUsed"].as_f64().unwrap_or(0.0));
        let w = round_pct(pu["apiPercentUsed"].as_f64().unwrap_or(0.0));
        let reset = match v["billingCycleEnd"].as_str() {
            Some(x) if !x.is_empty() => parse_reset(x),
            _ => match v["billingCycleEnd"].as_i64() {
                Some(n) => parse_reset(&n.to_string()),
                None => Reset::None,
            },
        };
        return Some(Usage {
            a_pct: clamp_pct(s),
            a_reset: reset.clone(),
            b_pct: clamp_pct(w),
            b_reset: reset,
        });
    }

    // Enterprise-style /auth/usage fallback: maxRequestUsage bucket の最大 used
    let mut best: Option<i64> = None;
    if let Some(obj) = v.as_object() {
        for bucket in obj.values() {
            let Some(b) = bucket.as_object() else {
                continue;
            };
            let max_u = b.get("maxRequestUsage").and_then(Value::as_f64).unwrap_or(0.0);
            if max_u == 0.0 {
                continue;
            }
            let num = b
                .get("numRequestsTotal")
                .or_else(|| b.get("numRequests"))
                .and_then(Value::as_f64)
                .unwrap_or(0.0);
            let used = (num * 100.0 / max_u).round() as i64;
            best = Some(best.map_or(used, |x| x.max(used)));
        }
    }
    best.map(|u| Usage {
        a_pct: u,
        a_reset: Reset::None,
        b_pct: u,
        b_reset: Reset::None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_plan_usage() {
        let v: Value = serde_json::from_str(
            r#"{"planUsage":{"limit":100,"includedSpend":42,
                "autoPercentUsed":10.4,"apiPercentUsed":3.6},
                "billingCycleEnd":1893456000000}"#,
        )
        .unwrap();
        let u = parse_usage(&v).unwrap();
        assert_eq!(u.a_pct, 10); // Cursor Models — includedSpend/limit の 42% は使わない
        assert_eq!(u.b_pct, 4); // Other Models
        assert_eq!(u.a_reset, Reset::Unix(1893456000)); // ms→s
    }

    // 実データ回帰: 実消費 4%/1% が旧式 (3344/7000) の 48% に化けていた。
    #[test]
    fn plan_usage_ignores_legacy_spend_ratio() {
        let v: Value = serde_json::from_str(
            r#"{"planUsage":{"limit":7000,"includedSpend":3344,"totalSpend":3344,
                "autoPercentUsed":4.1225,"apiPercentUsed":0.41818}}"#,
        )
        .unwrap();
        let u = parse_usage(&v).unwrap();
        assert_eq!(u.a_pct, 4);
        assert_eq!(u.b_pct, 1); // 0.42% → 0 ではなく 1 (ダッシュボード表記に一致)
    }

    #[test]
    fn parse_enterprise_fallback() {
        let v: Value = serde_json::from_str(
            r#"{"gpt4":{"maxRequestUsage":500,"numRequestsTotal":250},
                "other":{"maxRequestUsage":100,"numRequests":90}}"#,
        )
        .unwrap();
        let u = parse_usage(&v).unwrap();
        assert_eq!(u.a_pct, 90); // max(50, 90)
    }

    #[test]
    fn reset_normalizes_ms() {
        assert_eq!(parse_reset("1893456000000"), Reset::Unix(1893456000));
        assert_eq!(parse_reset("1893456000"), Reset::Unix(1893456000));
        assert_eq!(parse_reset("2026-07-18T10:00:00Z"), Reset::Iso("2026-07-18T10:00:00Z".into()));
    }

    #[test]
    fn cache_roundtrip() {
        let c = Cursor;
        let u = c.from_cache("42|10|1893456000").unwrap();
        assert_eq!(u.a_pct, 42);
        assert_eq!(u.b_pct, 10);
        assert_eq!(u.a_reset, Reset::Unix(1893456000));
        assert_eq!(u.a_reset, u.b_reset);
    }

    #[test]
    fn extract_token_variants() {
        assert_eq!(extract_token(r#"{"accessToken":"abc"}"#), Some("abc".into()));
        assert_eq!(extract_token(r#""plaintoken""#), Some("plaintoken".into()));
        assert_eq!(extract_token("rawtoken"), Some("rawtoken".into()));
    }
}
