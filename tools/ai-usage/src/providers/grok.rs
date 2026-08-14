// Grok / SuperGrok usage — ~/.grok/auth.json の session token で
// cli-chat-proxy.grok.com の billing を叩く。session token の寿命は 6h しかないので、
// 期限切れなら refresh_token grant (OIDC issuer の token endpoint) で自前に更新し
// auth.json へ書き戻す (grok CLI を起動していない間も表示を維持するため)。

use super::{Provider, Reset, Usage, clamp_pct, tmux_cache_path};
use crate::authstore;
use crate::http;
use anyhow::{Context, Result, anyhow};
use serde_json::{Value, json};
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

const API_KEY_SCOPE: &str = "xai::api_key";
const DEFAULT_PROXY: &str = "https://cli-chat-proxy.grok.com/v1";
const DEFAULT_ISSUER: &str = "https://auth.x.ai";

pub struct Grok;

fn home() -> String {
    std::env::var("HOME").unwrap_or_default()
}

fn grok_home() -> PathBuf {
    if let Ok(p) = std::env::var("GROK_HOME")
        && !p.is_empty()
    {
        return PathBuf::from(p);
    }
    PathBuf::from(home()).join(".grok")
}

fn auth_file() -> PathBuf {
    std::env::var("GROK_AUTH_FILE")
        .ok()
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| grok_home().join("auth.json"))
}

fn pi_auth_file() -> PathBuf {
    std::env::var("PI_AUTH_FILE")
        .ok()
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(home()).join(".pi/agent/auth.json"))
}

fn proxy_base() -> String {
    std::env::var("GROK_CLI_CHAT_PROXY_BASE_URL")
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| DEFAULT_PROXY.to_string())
}

/// pi `/login xai` の OAuth access token。API key は SuperGrok 週次枠ではないので使わない。
fn pi_oauth(store: &Value) -> Option<(String, String)> {
    let xai = store.get("xai")?;
    if xai.get("type").and_then(Value::as_str) != Some("oauth") {
        return None;
    }
    let access = xai
        .get("access")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())?
        .to_string();
    Some((access, String::new()))
}

/// session scope の (scope, entry) を返す。API key scope は SuperGrok 週次枠ではないので使わない。
fn session_entry(store: &Value) -> Option<(String, Value)> {
    let obj = store.as_object()?;
    let mut fallback = None;
    for (scope, entry) in obj {
        if scope == API_KEY_SCOPE {
            continue;
        }
        if entry
            .get("key")
            .and_then(Value::as_str)
            .unwrap_or("")
            .is_empty()
        {
            continue;
        }
        let mode = entry.get("auth_mode").and_then(Value::as_str).unwrap_or("");
        let pair = (scope.clone(), entry.clone());
        if matches!(mode, "oidc" | "web_login" | "external") {
            return Some(pair);
        }
        fallback.get_or_insert(pair);
    }
    fallback
}

fn entry_auth(entry: &Value) -> (String, String) {
    let key = entry
        .get("key")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let user_id = entry
        .get("user_id")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    (key, user_id)
}

fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// entry の失効時刻 (unix 秒)。フィールドが無い / 解釈できない場合は 0 = 不明。
fn expires_at_secs(entry: &Value) -> i64 {
    let s = entry
        .get("expires_at")
        .and_then(Value::as_str)
        .unwrap_or("");
    match s.parse::<jiff::Timestamp>() {
        Ok(ts) => ts.as_second(),
        Err(_) => 0,
    }
}

fn token_url(entry: &Value) -> String {
    if let Ok(u) = std::env::var("GROK_TOKEN_URL")
        && !u.is_empty()
    {
        return u;
    }
    let issuer = entry
        .get("oidc_issuer")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .unwrap_or(DEFAULT_ISSUER);
    format!("{}/oauth2/token", issuer.trim_end_matches('/'))
}

/// 期限切れ session を refresh_token grant で更新し、auth.json へ書き戻す。
/// 戻り値: (access_token, user_id)。
///
/// ponytail: 排他は ai-usage 同士のみ (grok CLI は auth.json.lock で独自プロトコル)。
/// 書き込みは atomic rename なので CLI が壊れた JSON を読むことはないが、CLI 側の
/// 書き戻しと交差すると lost update で 1 回 refresh が無駄になる。実害は次回の
/// refresh で解消するため、CLI の lock 形式に追従するのはそれが問題になってから。
fn refresh_session(scope: &str) -> Result<(String, String)> {
    let path = auth_file();
    let path_str = path.to_string_lossy().to_string();
    let _lock = authstore::lock(&format!(
        "{}.refresh.lock",
        tmux_cache_path("grok_usage").display()
    ))?;

    // lock 待ちの間に他プロセスが更新している可能性があるので読み直す。
    let body =
        std::fs::read_to_string(&path).with_context(|| format!("reading {}", path.display()))?;
    let mut store: Value = serde_json::from_str(body.trim()).context("parsing grok auth.json")?;
    let entry = store
        .get(scope)
        .cloned()
        .ok_or_else(|| anyhow!("grok auth scope vanished"))?;
    let (key, user_id) = entry_auth(&entry);
    if !key.is_empty() && expires_at_secs(&entry) > now_secs() + 60 {
        return Ok((key, user_id));
    }

    let refresh = entry
        .get("refresh_token")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| anyhow!("no grok refresh_token"))?;
    let client_id = entry
        .get("oidc_client_id")
        .and_then(Value::as_str)
        .unwrap_or("");
    let mut res = http::agent()
        .post(token_url(&entry))
        .send_form([
            ("grant_type", "refresh_token"),
            ("refresh_token", refresh),
            ("client_id", client_id),
        ])
        .context("grok token refresh")?;
    let r: Value = serde_json::from_str(&res.body_mut().read_to_string()?)
        .context("parsing refresh response")?;
    let access = r["access_token"]
        .as_str()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| anyhow!("refresh returned no access_token"))?
        .to_string();
    let new_refresh = r["refresh_token"].as_str().unwrap_or(refresh).to_string();
    let expires_in = r["expires_in"].as_i64().unwrap_or(0);

    let e = &mut store[scope];
    e["key"] = json!(access);
    e["refresh_token"] = json!(new_refresh);
    if expires_in > 0 {
        e["expires_at"] = json!(authstore::iso_from_unix(now_secs() + expires_in));
    }
    authstore::write_json(&path_str, &store)?;
    Ok((access, user_id))
}

fn cents(v: &Value) -> Option<i64> {
    v.get("val").and_then(Value::as_i64).or_else(|| v.as_i64())
}

fn reset_of(s: Option<&str>) -> Reset {
    match s {
        Some(s) if !s.is_empty() => Reset::Iso(s.to_string()),
        _ => Reset::None,
    }
}

fn parse_billing(v: &Value) -> Option<Usage> {
    let cfg = v.get("config").unwrap_or(v);
    if !cfg.is_object() {
        return None;
    }

    let weekly = cfg
        .get("creditUsagePercent")
        .or_else(|| cfg.get("credit_usage_percent"))
        .and_then(Value::as_f64)
        .map(|p| clamp_pct(p.round() as i64))
        .or_else(|| {
            let used = cfg.get("used").and_then(cents)?;
            let limit = cfg.get("monthlyLimit").or_else(|| cfg.get("monthly_limit")).and_then(cents)?;
            if limit <= 0 {
                return None;
            }
            Some(clamp_pct((used * 100 + limit / 2) / limit))
        })?;

    let period = cfg.get("currentPeriod").or_else(|| cfg.get("current_period"));
    let weekly_reset = reset_of(
        period
            .and_then(|p| p.get("end"))
            .and_then(Value::as_str)
            .or_else(|| {
                cfg.get("billingPeriodEnd")
                    .or_else(|| cfg.get("billing_period_end"))
                    .and_then(Value::as_str)
            }),
    );

    let extra_used = cfg
        .get("onDemandUsed")
        .or_else(|| cfg.get("on_demand_used"))
        .and_then(cents)
        .unwrap_or(0);
    let extra_cap = cfg
        .get("onDemandCap")
        .or_else(|| cfg.get("on_demand_cap"))
        .and_then(cents)
        .unwrap_or(0);
    let extra = if extra_cap > 0 {
        clamp_pct((extra_used * 100 + extra_cap / 2) / extra_cap)
    } else {
        0
    };

    Some(Usage {
        a_pct: weekly,
        a_reset: weekly_reset,
        b_pct: extra,
        b_reset: Reset::None,
        ..Usage::default()
    })
}

impl Grok {
    fn token(&self) -> Result<(String, String)> {
        if let Ok(t) = std::env::var("GROK_AUTH_TOKEN")
            && !t.is_empty()
        {
            return Ok((t, String::new()));
        }
        if let Ok(body) = std::fs::read_to_string(auth_file())
            && let Ok(v) = serde_json::from_str::<Value>(body.trim())
            && let Some((scope, entry)) = session_entry(&v)
        {
            let (key, user_id) = entry_auth(&entry);
            let exp = expires_at_secs(&entry);
            if exp == 0 || exp > now_secs() + 60 {
                return Ok((key, user_id));
            }
            // 期限切れ: refresh に失敗したら pi 側の token へ落とす。
            if let Ok(auth) = refresh_session(&scope) {
                return Ok(auth);
            }
        }
        let path = pi_auth_file();
        let body = std::fs::read_to_string(&path)
            .with_context(|| format!("reading {}", path.display()))?;
        let v: Value = serde_json::from_str(body.trim()).context("parsing pi auth.json")?;
        pi_oauth(&v).ok_or_else(|| anyhow!("no grok session token"))
    }
}

impl Provider for Grok {
    fn icon(&self) -> &'static str {
        "\u{f135}" // 
    }

    fn labels(&self) -> (&'static str, &'static str) {
        ("weekly", "extra")
    }

    fn cache_path(&self) -> PathBuf {
        tmux_cache_path("grok_usage")
    }

    fn fetch(&self) -> Result<Usage> {
        let (token, user_id) = self.token()?;
        let url = format!("{}/billing?format=credits", proxy_base().trim_end_matches('/'));
        let mut req = http::agent()
            .get(&url)
            .header("Authorization", &format!("Bearer {token}"))
            .header("X-XAI-Token-Auth", "xai-grok-cli");
        if !user_id.is_empty() {
            req = req.header("x-userid", &user_id);
        }
        let mut res = req.call().context("grok billing request")?;
        let body = res.body_mut().read_to_string().context("reading body")?;
        let v: Value = serde_json::from_str(&body).context("parsing billing json")?;
        parse_billing(&v).ok_or_else(|| anyhow!("no usable grok billing"))
    }

    fn to_cache(&self, u: &Usage) -> String {
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
    fn parse_weekly_credits() {
        let v: Value = serde_json::from_str(
            r#"{
                "config": {
                    "creditUsagePercent": 42.4,
                    "currentPeriod": {"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-08-20T00:00:00Z"},
                    "onDemandUsed": {"val": 25},
                    "onDemandCap": {"val": 100}
                }
            }"#,
        )
        .unwrap();
        let u = parse_billing(&v).unwrap();
        assert_eq!(u.a_pct, 42);
        assert_eq!(u.a_reset, Reset::Iso("2026-08-20T00:00:00Z".into()));
        assert_eq!(u.b_pct, 25);
        assert_eq!(u.b_reset, Reset::None);
    }

    #[test]
    fn parse_legacy_monthly_limit() {
        let v: Value = serde_json::from_str(
            r#"{"config":{"used":{"val":1234},"monthlyLimit":{"val":2000},"billingPeriodEnd":"2026-09-01T00:00:00Z"}}"#,
        )
        .unwrap();
        let u = parse_billing(&v).unwrap();
        assert_eq!(u.a_pct, 62);
        assert_eq!(u.a_reset, Reset::Iso("2026-09-01T00:00:00Z".into()));
        assert_eq!(u.b_pct, 0);
    }

    #[test]
    fn session_entry_skips_api_key() {
        let v: Value = serde_json::from_str(
            r#"{
                "xai::api_key": {"key":"xai-secret","user_id":"u0","auth_mode":"api_key"},
                "https://auth.x.ai": {"key":"sess","user_id":"u1","auth_mode":"oidc"}
            }"#,
        )
        .unwrap();
        let (scope, entry) = session_entry(&v).unwrap();
        assert_eq!(scope, "https://auth.x.ai");
        assert_eq!(entry_auth(&entry), ("sess".into(), "u1".into()));
    }

    #[test]
    fn expires_at_and_token_url() {
        let entry: Value = serde_json::from_str(
            r#"{"expires_at":"2026-08-13T12:01:52.094913Z","oidc_issuer":"https://auth.x.ai/"}"#,
        )
        .unwrap();
        assert_eq!(expires_at_secs(&entry), 1786622512);
        assert_eq!(token_url(&entry), "https://auth.x.ai/oauth2/token");
        // expires_at が無い形式は「不明」= refresh せず現 token を使う。
        assert_eq!(expires_at_secs(&json!({})), 0);
        assert_eq!(token_url(&json!({})), "https://auth.x.ai/oauth2/token");
    }

    #[test]
    fn pi_oauth_reads_access() {
        let v: Value = serde_json::from_str(
            r#"{"xai":{"type":"oauth","access":"sess","refresh":"rt"}}"#,
        )
        .unwrap();
        assert_eq!(pi_oauth(&v), Some(("sess".into(), "".into())));
        let key_only: Value =
            serde_json::from_str(r#"{"xai":{"type":"api_key","key":"xai-secret"}}"#).unwrap();
        assert_eq!(pi_oauth(&key_only), None);
    }

    #[test]
    fn cache_roundtrip() {
        let g = Grok;
        let u = Usage {
            a_pct: 42,
            a_reset: Reset::Iso("2026-08-20T00:00:00Z".into()),
            b_pct: 10,
            b_reset: Reset::None,
            ..Usage::default()
        };
        let line = g.to_cache(&u);
        assert_eq!(line, "42|10|2026-08-20T00:00:00Z|");
        assert_eq!(g.from_cache(&line), Some(u));
    }
}
