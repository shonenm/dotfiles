// Gemini usage — ~/.gemini/oauth_creds.json の Google OAuth token で Code Assist quota を取得。
// refresh は持たない (client secret 無し)。期限切れ token は placeholder (CLI 再起動を促す)。

use super::{Provider, Reset, Usage, tmux_cache_path};
use crate::http;
use anyhow::{Context, Result, anyhow};
use serde_json::{Value, json};
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

pub struct Gemini;

fn home() -> String {
    std::env::var("HOME").unwrap_or_default()
}

impl Gemini {
    /// (access_token, expiry_date_ms) を読む。
    fn creds(&self) -> Result<(String, i64)> {
        let path = format!("{}/.gemini/oauth_creds.json", home());
        let body = std::fs::read_to_string(&path).with_context(|| format!("reading {path}"))?;
        let v: Value = serde_json::from_str(&body).context("parsing oauth_creds.json")?;
        let at = v["access_token"]
            .as_str()
            .filter(|s| !s.is_empty())
            .ok_or_else(|| anyhow!("no access_token"))?
            .to_string();
        let ex = v["expiry_date"].as_i64().unwrap_or(0);
        Ok((at, ex))
    }

    /// GOOGLE_CLOUD_PROJECT > ~/.gemini/projects.json の最初のエントリ。
    fn project_id(&self) -> String {
        if let Ok(p) = std::env::var("GOOGLE_CLOUD_PROJECT")
            && !p.is_empty()
        {
            return p;
        }
        let path = format!("{}/.gemini/projects.json", home());
        let Ok(body) = std::fs::read_to_string(&path) else {
            return String::new();
        };
        let Ok(v) = serde_json::from_str::<Value>(&body) else {
            return String::new();
        };
        if let Some(map) = v.as_object() {
            for val in map.values() {
                if let Some(s) = val.as_str()
                    && !s.is_empty()
                {
                    return s.to_string();
                }
                if let Some(obj) = val.as_object() {
                    for k in ["project", "projectId", "cloudaicompanionProject"] {
                        if let Some(s) = obj.get(k).and_then(Value::as_str)
                            && !s.is_empty()
                        {
                            return s.to_string();
                        }
                    }
                }
            }
        }
        String::new()
    }
}

impl Provider for Gemini {
    fn icon(&self) -> &'static str {
        "\u{f0ae2}" // 󰫢
    }

    fn labels(&self) -> (&'static str, &'static str) {
        ("current", "weekly")
    }

    fn cache_path(&self) -> PathBuf {
        tmux_cache_path("gemini_usage")
    }

    fn fetch(&self) -> Result<Usage> {
        let (token, expiry_ms) = self.creds()?;
        // expiry_date は ms epoch。期限切れなら fail (CLI 再起動を促す)。
        let now_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0);
        if expiry_ms > 0 && expiry_ms < now_ms {
            return Err(anyhow!("access token expired"));
        }

        let project = self.project_id();
        let payload = serde_json::to_vec(&json!({ "project": project })).context("payload")?;
        let mut res = http::agent()
            .post("https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")
            .header("Authorization", &format!("Bearer {token}"))
            .header("Content-Type", "application/json")
            .send(&payload)
            .context("quota request")?;
        let body = res.body_mut().read_to_string().context("reading body")?;
        let v: Value = serde_json::from_str(&body).context("parsing quota json")?;

        parse_quota(&v).ok_or_else(|| anyhow!("no usable buckets"))
    }

    fn to_cache(&self, u: &Usage) -> String {
        // bash: "{s}|{w}|{r1_iso}|{r2_iso}"
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

/// buckets を used 降順 sort し top2 を current/weekly に。
fn parse_quota(v: &Value) -> Option<Usage> {
    let buckets = v["buckets"].as_array()?;
    let mut scored: Vec<(f64, Reset)> = Vec::new();
    for b in buckets {
        let Some(rf) = b["remainingFraction"].as_f64() else {
            continue;
        };
        let used = (1.0 - rf).clamp(0.0, 1.0);
        let reset = match b["resetTime"].as_str() {
            Some(s) if !s.is_empty() => Reset::Iso(s.to_string()),
            _ => Reset::None,
        };
        scored.push((used, reset));
    }
    if scored.is_empty() {
        return None;
    }
    scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
    let s = (scored[0].0 * 100.0).round() as i64;
    let r1 = scored[0].1.clone();
    let (w, r2) = if scored.len() > 1 {
        ((scored[1].0 * 100.0).round() as i64, scored[1].1.clone())
    } else {
        (s, r1.clone())
    };
    Some(Usage {
        a_pct: s,
        a_reset: r1,
        b_pct: w,
        b_reset: r2,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_quota_top2_by_used() {
        let v: Value = serde_json::from_str(
            r#"{"buckets":[
                {"remainingFraction":0.9,"resetTime":"2026-07-18T10:00:00Z"},
                {"remainingFraction":0.2,"resetTime":"2026-07-25T10:00:00Z"},
                {"remainingFraction":0.5,"resetTime":""}
            ]}"#,
        )
        .unwrap();
        let u = parse_quota(&v).unwrap();
        assert_eq!(u.a_pct, 80); // used 0.8 (rf 0.2)
        assert_eq!(u.a_reset, Reset::Iso("2026-07-25T10:00:00Z".into()));
        assert_eq!(u.b_pct, 50); // used 0.5
        assert_eq!(u.b_reset, Reset::None);
    }

    #[test]
    fn parse_quota_single_bucket_mirrors() {
        let v: Value =
            serde_json::from_str(r#"{"buckets":[{"remainingFraction":0.4,"resetTime":""}]}"#)
                .unwrap();
        let u = parse_quota(&v).unwrap();
        assert_eq!(u.a_pct, 60);
        assert_eq!(u.b_pct, 60);
    }

    #[test]
    fn parse_quota_empty_none() {
        let v: Value = serde_json::from_str(r#"{"buckets":[]}"#).unwrap();
        assert!(parse_quota(&v).is_none());
    }
}
