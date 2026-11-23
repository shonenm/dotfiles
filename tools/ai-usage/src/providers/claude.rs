// Claude usage — mac: Keychain / linux: .credentials.json の OAuth token で
// api.anthropic.com/api/oauth/usage を叩く。refresh は無し。
// 既定アカウント (~/.claude) に加え、claude-as の各アカウント
// (${XDG_STATE_HOME:-~/.local/state}/claude-accounts/<name>) も 1 アカウント 2 行で出す。

use super::{Provider, Reset, Usage, clamp_pct, tmux_cache_path};
use crate::http;
use anyhow::{Context, Result, anyhow};
use serde_json::Value;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};

pub struct Claude {
    /// claude-as のアカウント名。None は既定アカウント。
    account: Option<String>,
}

fn accounts_dir() -> String {
    // claude-as と同じ文字列を組み立てる (mac の Keychain 名はこの path の hash)
    let state = std::env::var("XDG_STATE_HOME")
        .unwrap_or_else(|_| format!("{}/.local/state", std::env::var("HOME").unwrap_or_default()));
    format!("{state}/claude-accounts")
}

/// Claude Code が CLAUDE_CONFIG_DIR ごとに付ける Keychain 名の suffix (sha256 先頭 8 桁)。
fn keychain_suffix(dir: &str) -> Result<String> {
    let mut child = Command::new("shasum")
        .args(["-a", "256"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .context("running shasum")?;
    child
        .stdin
        .take()
        .context("shasum stdin")?
        .write_all(dir.as_bytes())?;
    let out = child.wait_with_output()?;
    let hex = String::from_utf8(out.stdout)?;
    hex.get(..8)
        .map(|h| format!("-{h}"))
        .ok_or_else(|| anyhow!("shasum output"))
}

impl Claude {
    /// 既定アカウントと claude-as の全アカウント (名前順)。
    pub fn accounts() -> Vec<Claude> {
        let mut names: Vec<String> = std::fs::read_dir(accounts_dir())
            .map(|rd| {
                rd.flatten()
                    .filter(|e| e.path().is_dir())
                    .filter_map(|e| e.file_name().into_string().ok())
                    .collect()
            })
            .unwrap_or_default();
        names.sort();
        std::iter::once(None)
            .chain(names.into_iter().map(Some))
            .map(|account| Claude { account })
            .collect()
    }

    fn config_dir(&self) -> Option<String> {
        self.account
            .as_ref()
            .map(|n| format!("{}/{n}", accounts_dir()))
    }

    /// claude-as のアカウントは label に名前を前置する ("utokyo current")。
    fn with_labels(&self, mut u: Usage) -> Usage {
        if let Some(n) = &self.account {
            let (a, b) = self.labels();
            u.labels = Some((format!("{n} {a}"), Some(format!("{n} {b}"))));
        }
        u
    }

    fn token(&self) -> Result<String> {
        let dir = self.config_dir();
        let creds = if cfg!(target_os = "macos") {
            let suffix = match &dir {
                Some(d) => keychain_suffix(d)?,
                None => String::new(),
            };
            let out = Command::new("security")
                .args([
                    "find-generic-password",
                    "-s",
                    &format!("Claude Code-credentials{suffix}"),
                    "-w",
                ])
                .output()
                .context("running security")?;
            if !out.status.success() {
                return Err(anyhow!("keychain lookup failed"));
            }
            String::from_utf8(out.stdout).context("keychain output utf8")?
        } else {
            let dir = dir.unwrap_or(format!("{}/.claude", std::env::var("HOME")?));
            let path = format!("{dir}/.credentials.json");
            std::fs::read_to_string(&path).with_context(|| format!("reading {path}"))?
        };
        let v: Value = serde_json::from_str(creds.trim()).context("parsing credentials json")?;
        v["claudeAiOauth"]["accessToken"]
            .as_str()
            .map(str::to_string)
            .ok_or_else(|| anyhow!("no accessToken in credentials"))
    }
}

fn window(v: &Value, key: &str) -> (i64, Reset) {
    let util = v[key]["utilization"].as_f64().unwrap_or(0.0);
    let pct = clamp_pct(util.round() as i64);
    let reset = match v[key]["resets_at"].as_str() {
        Some(s) if !s.is_empty() => Reset::Iso(s.to_string()),
        _ => Reset::None,
    };
    (pct, reset)
}

impl Provider for Claude {
    fn icon(&self) -> &'static str {
        "\u{f06c4}" // 󰛄
    }

    fn labels(&self) -> (&'static str, &'static str) {
        ("current", "weekly")
    }

    fn cache_path(&self) -> PathBuf {
        match &self.account {
            Some(n) => tmux_cache_path(&format!("claude_usage_{n}")),
            None => tmux_cache_path("claude_usage"),
        }
    }

    fn fetch(&self) -> Result<Usage> {
        let token = self.token()?;
        let mut res = http::agent()
            .get("https://api.anthropic.com/api/oauth/usage")
            .header("Authorization", &format!("Bearer {token}"))
            .header("anthropic-beta", "oauth-2025-04-20")
            .call()
            .context("usage request")?;
        let body = res.body_mut().read_to_string().context("reading body")?;
        let v: Value = serde_json::from_str(&body).context("parsing usage json")?;
        let (a_pct, a_reset) = window(&v, "five_hour");
        let (b_pct, b_reset) = window(&v, "seven_day");
        Ok(self.with_labels(Usage {
            a_pct,
            a_reset,
            b_pct,
            b_reset,
            ..Usage::default()
        }))
    }

    fn to_cache(&self, u: &Usage) -> String {
        // bash: "{s}|{w}|{r5_iso}|{r7_iso}"
        format!(
            "{}|{}|{}|{}",
            u.a_pct,
            u.b_pct,
            u.a_reset.to_field(),
            u.b_reset.to_field()
        )
    }

    fn from_cache(&self, line: &str) -> Option<Usage> {
        super::parse_two_iso_cache(line).map(|u| self.with_labels(u))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cache_roundtrip() {
        let c = Claude { account: None };
        let u = Usage {
            a_pct: 42,
            a_reset: Reset::Iso("2026-07-18T10:00:00Z".into()),
            b_pct: 88,
            b_reset: Reset::None,
            ..Usage::default()
        };
        let line = c.to_cache(&u);
        assert_eq!(line, "42|88|2026-07-18T10:00:00Z|");
        assert_eq!(c.from_cache(&line), Some(u));
    }

    #[test]
    fn parse_usage_json() {
        let v: Value = serde_json::from_str(
            r#"{"five_hour":{"utilization":42.6,"resets_at":"2026-07-18T10:00:00Z"},
                "seven_day":{"utilization":150,"resets_at":null}}"#,
        )
        .unwrap();
        let (a, ar) = window(&v, "five_hour");
        let (b, br) = window(&v, "seven_day");
        assert_eq!(a, 43); // round(42.6)
        assert_eq!(ar, Reset::Iso("2026-07-18T10:00:00Z".into()));
        assert_eq!(b, 100); // clamp(150)
        assert_eq!(br, Reset::None);
    }

    #[test]
    fn from_cache_rejects_garbage() {
        let c = Claude { account: None };
        assert_eq!(c.from_cache("notanumber|5|"), None);
        assert_eq!(c.from_cache(""), None);
    }

    #[test]
    fn account_labels_and_cache_path() {
        let c = Claude {
            account: Some("utokyo".into()),
        };
        let u = c.from_cache("1|2||").unwrap();
        assert_eq!(
            u.labels,
            Some(("utokyo current".into(), Some("utokyo weekly".into())))
        );
        assert!(c.cache_path().ends_with("tmux/claude_usage_utokyo"));
        assert_eq!(
            Claude { account: None }.from_cache("1|2||").unwrap().labels,
            None
        );
    }

    #[test]
    fn keychain_suffix_is_sha256_prefix() {
        // printf %s /x | shasum -a 256
        assert_eq!(keychain_suffix("/x").unwrap(), "-b3d1db31");
    }
}
