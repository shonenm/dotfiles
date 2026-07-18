// Claude usage — mac: Keychain / linux: ~/.claude/.credentials.json の OAuth token で
// api.anthropic.com/api/oauth/usage を叩く。refresh は無し。

use super::{Provider, Reset, Usage, clamp_pct, tmux_cache_path};
use crate::http;
use anyhow::{Context, Result, anyhow};
use serde_json::Value;
use std::path::PathBuf;
use std::process::Command;

pub struct Claude;

impl Claude {
    fn token(&self) -> Result<String> {
        let creds = if cfg!(target_os = "macos") {
            let out = Command::new("security")
                .args(["find-generic-password", "-s", "Claude Code-credentials", "-w"])
                .output()
                .context("running security")?;
            if !out.status.success() {
                return Err(anyhow!("keychain lookup failed"));
            }
            String::from_utf8(out.stdout).context("keychain output utf8")?
        } else {
            let path = format!("{}/.claude/.credentials.json", std::env::var("HOME")?);
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
        tmux_cache_path("claude_usage")
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
        Ok(Usage {
            a_pct,
            a_reset,
            b_pct,
            b_reset,
        })
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
        super::parse_two_iso_cache(line)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cache_roundtrip() {
        let c = Claude;
        let u = Usage {
            a_pct: 42,
            a_reset: Reset::Iso("2026-07-18T10:00:00Z".into()),
            b_pct: 88,
            b_reset: Reset::None,
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
        assert_eq!(Claude.from_cache("notanumber|5|"), None);
        assert_eq!(Claude.from_cache(""), None);
    }
}
