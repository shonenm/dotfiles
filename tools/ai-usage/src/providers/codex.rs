// Codex (OpenAI) usage — ~/.codex/auth.json の OAuth token。Codex CLI と同じ
// refresh-token flow を持つ (期限切れ access_token を使うと usage が 401 で落ちる)。
// refresh は fcntl 排他ロック下で行い、auth.json を tmp+chmod+rename で atomic 更新する。

use super::{Provider, Reset, Usage, clamp_pct};
use crate::authstore;
use crate::http;
use anyhow::{Context, Result, anyhow};
use base64::Engine;
use serde_json::{Value, json};
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

const DAY: f64 = 24.0 * 60.0 * 60.0;

pub struct Codex;

fn env_or(key: &str, default: &str) -> String {
    std::env::var(key).unwrap_or_else(|_| default.to_string())
}

fn auth_file() -> String {
    std::env::var("CODEX_AUTH_FILE")
        .unwrap_or_else(|_| format!("{}/.codex/auth.json", std::env::var("HOME").unwrap_or_default()))
}

fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// JWT の payload (2 番目のセグメント) を検証せずデコード。
fn jwt_payload(jwt: &str) -> Value {
    let Some(seg) = jwt.split('.').nth(1) else {
        return Value::Null;
    };
    match base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(seg) {
        Ok(bytes) => serde_json::from_slice(&bytes).unwrap_or(Value::Null),
        Err(_) => Value::Null,
    }
}

/// tokens.account_id → d.account_id → id_token JWT claim の順で account_id を決める。
fn account_id(tokens: &Value, d: &Value) -> String {
    for v in [&tokens["account_id"], &d["account_id"]] {
        if let Some(s) = v.as_str()
            && !s.is_empty()
        {
            return s.to_string();
        }
    }
    let claim = jwt_payload(tokens["id_token"].as_str().unwrap_or(""));
    claim["https://api.openai.com/auth"]["chatgpt_account_id"]
        .as_str()
        .unwrap_or("")
        .to_string()
}

struct Auth {
    token: String,
    account_id: String,
    refresh_token: String,
    access_exp: i64,
}

impl Codex {
    fn read_auth(&self) -> Result<Auth> {
        let body = fs::read_to_string(auth_file()).context("reading auth.json")?;
        let d: Value = serde_json::from_str(&body).context("parsing auth.json")?;
        let tokens = &d["tokens"];
        let token = tokens["access_token"].as_str().unwrap_or("").to_string();
        let acc = account_id(tokens, &d);
        let refresh = tokens["refresh_token"].as_str().unwrap_or("").to_string();
        let exp = jwt_payload(&token)["exp"].as_i64().unwrap_or(0);
        Ok(Auth {
            token,
            account_id: acc,
            refresh_token: refresh,
            access_exp: exp,
        })
    }

    /// 排他ロック下で auth.json を読み、期限内なら現 token を返す。期限切れなら
    /// refresh POST → tokens 更新 → atomic 保存し新 token を返す。
    /// `rejected` にサーバが拒否した token を渡すと JWT の exp が未来でも refresh する
    /// (exp より前に失効させられることがあり、exp を信じると復旧できない)。
    /// 戻り値: (access_token, account_id)。
    fn refresh_auth(&self, rejected: Option<&str>) -> Result<(String, String)> {
        let path = auth_file();
        let _lock = authstore::lock(&format!("{}.refresh.lock", cache_base()))?; // drop で解放

        let body = fs::read_to_string(&path).context("reading auth.json")?;
        let mut d: Value = serde_json::from_str(&body).context("parsing auth.json")?;
        let access = d["tokens"]["access_token"].as_str().unwrap_or("").to_string();
        let acc = account_id(&d["tokens"], &d);
        let exp = jwt_payload(&access)["exp"].as_i64().unwrap_or(0);
        // 拒否された token 自身は期限内に見えても使わない。ファイル側が別 token に
        // 差し替わっていれば (他プロセスが refresh 済み) それを再利用する。
        if !access.is_empty() && exp > now_secs() + 60 && rejected != Some(access.as_str()) {
            return Ok((access, acc));
        }

        let refresh = d["tokens"]["refresh_token"]
            .as_str()
            .filter(|s| !s.is_empty())
            .ok_or_else(|| anyhow!("no refresh_token"))?
            .to_string();

        let refresh_url = env_or("CODEX_REFRESH_URL", "https://auth.openai.com/oauth/token");
        let client_id = env_or("CODEX_CLIENT_ID", "app_EMoamEEZ73f0CkXaXp7hrann");
        let payload = serde_json::to_vec(&json!({
            "client_id": client_id,
            "grant_type": "refresh_token",
            "refresh_token": refresh,
        }))?;
        let mut res = http::agent()
            .post(&refresh_url)
            .header("Content-Type", "application/json")
            .send(&payload)
            .context("refresh request")?;
        let r: Value = serde_json::from_str(&res.body_mut().read_to_string()?)
            .context("parsing refresh response")?;

        let new_access = r["access_token"].as_str().unwrap_or(&access).to_string();
        let new_refresh = r["refresh_token"].as_str().unwrap_or(&refresh).to_string();
        let new_id = r["id_token"]
            .as_str()
            .or_else(|| d["tokens"]["id_token"].as_str())
            .unwrap_or("")
            .to_string();

        d["tokens"]["access_token"] = json!(new_access);
        d["tokens"]["refresh_token"] = json!(new_refresh);
        if !new_id.is_empty() {
            d["tokens"]["id_token"] = json!(new_id);
        }
        let new_acc = account_id(&d["tokens"], &d);
        if !new_acc.is_empty() {
            d["tokens"]["account_id"] = json!(new_acc);
        }
        d["last_refresh"] = json!(authstore::iso_now());

        authstore::write_json(&path, &d)?;
        Ok((new_access, new_acc))
    }

    fn fetch_usage(&self, token: &str, account_id: &str) -> Option<String> {
        let url = env_or("CODEX_USAGE_URL", "https://chatgpt.com/backend-api/wham/usage");
        let mut req = http::agent()
            .get(&url)
            .header("Authorization", &format!("Bearer {token}"))
            .header("User-Agent", "codex-cli");
        if !account_id.is_empty() {
            req = req.header("ChatGPT-Account-Id", account_id);
        }
        req.call()
            .ok()
            .and_then(|mut r| r.body_mut().read_to_string().ok())
            .filter(|s| !s.is_empty())
    }
}

fn cache_base() -> String {
    std::env::var("CODEX_USAGE_CACHE").unwrap_or_else(|_| {
        let base = std::env::var("XDG_CACHE_HOME")
            .unwrap_or_else(|_| format!("{}/.cache", std::env::var("HOME").unwrap_or_default()));
        format!("{base}/tmux/codex_usage")
    })
}

impl Provider for Codex {
    fn icon(&self) -> &'static str {
        "\u{f0768}" // 󰝨
    }

    fn labels(&self) -> (&'static str, &'static str) {
        ("current", "weekly")
    }

    fn cache_path(&self) -> PathBuf {
        PathBuf::from(cache_base())
    }

    fn fetch(&self) -> Result<Usage> {
        let auth = self.read_auth()?;
        let mut token = auth.token;
        let mut acc = auth.account_id;
        let mut refresh_attempted = false;

        // access_token 欠損 or 期限切れ (60s 猶予) なら先に refresh。
        if !auth.refresh_token.is_empty()
            && (token.is_empty() || (auth.access_exp > 0 && auth.access_exp <= now_secs() + 60))
        {
            refresh_attempted = true;
            let (t, a) = self.refresh_auth(None)?;
            if t.is_empty() {
                return Err(anyhow!("refresh yielded empty token"));
            }
            token = t;
            acc = a;
        }
        if token.is_empty() {
            return Err(anyhow!("no access token"));
        }

        // usage 取得。401 等で空なら refresh_token が生きていれば 1 回だけ復旧。
        // 拒否された token を渡し、exp が未来でも refresh を走らせる。
        let mut raw = self.fetch_usage(&token, &acc);
        if raw.is_none() && !auth.refresh_token.is_empty() && !refresh_attempted {
            let (t, a) = self.refresh_auth(Some(&token))?;
            if !t.is_empty() {
                raw = self.fetch_usage(&t, &a);
            }
        }
        let raw = raw.ok_or_else(|| anyhow!("usage fetch failed"))?;
        let v: Value = serde_json::from_str(&raw).context("parsing usage json")?;
        parse_usage(&v).ok_or_else(|| anyhow!("no usable windows"))
    }

    fn to_cache(&self, u: &Usage) -> String {
        // "v3|{a}|{b}|{a_resets_unix}|{b_resets_unix}|{a_label}|{b_label}"
        // ラベルは plan で変わる (free は 30d 枠のみ) ので cache にも載せる。
        // b_label が空なら window 自体が無い。
        let (la, lb) = match &u.labels {
            Some((a, b)) => (a.clone(), b.clone().unwrap_or_default()),
            None => {
                let (a, b) = self.labels();
                (a.to_string(), b.to_string())
            }
        };
        format!(
            "v3|{}|{}|{}|{}|{}|{}",
            u.a_pct,
            u.b_pct,
            u.a_reset.to_field(),
            u.b_reset.to_field(),
            la,
            lb
        )
    }

    fn from_cache(&self, line: &str) -> Option<Usage> {
        let f: Vec<&str> = line.split('|').collect();
        if f.first() != Some(&"v3") {
            return None;
        }
        let a_pct: i64 = f.get(1)?.parse().ok()?;
        let b_pct: i64 = f.get(2)?.parse().ok()?;
        let unix = |i: usize| match f.get(i).and_then(|s| s.parse::<i64>().ok()) {
            Some(n) => Reset::Unix(n),
            None => Reset::None,
        };
        let la = f.get(5).filter(|s| !s.is_empty())?.to_string();
        let lb = f.get(6).filter(|s| !s.is_empty()).map(|s| s.to_string());
        Some(Usage {
            a_pct,
            a_reset: unix(3),
            b_pct,
            b_reset: unix(4),
            labels: Some((la, lb)),
        })
    }
}

/// window 長からラベルを決める。plan により枠の構成が変わる (Plus は 5h + 7d、
/// free は 30d のみ) ため、固定ラベルではなく実際の window 長に合わせる。
fn window_label(secs: f64) -> String {
    let near = |target: f64| (target * 0.95..=target * 1.05).contains(&secs);
    if near(7.0 * DAY) {
        return "weekly".to_string();
    }
    if near(30.0 * DAY) {
        return "monthly".to_string();
    }
    if secs < DAY {
        return "current".to_string(); // 5h 等の短期枠
    }
    format!("{}d", (secs / DAY).round() as i64)
}

/// rate_limit の window を短い順に並べ、1 行目=短期枠 / 2 行目=長期枠として返す。
/// ラベルは window 長から導く。存在しない window は行を出さない
/// (0% と描くと「未使用の週次枠がある」ように見えてしまう)。
fn parse_usage(v: &Value) -> Option<Usage> {
    let rl = &v["rate_limit"];
    let mut windows: Vec<(f64, &Value)> = Vec::new();
    for k in ["primary_window", "secondary_window"] {
        let w = &rl[k];
        if w.is_object() && !w.as_object().unwrap().is_empty() {
            windows.push((w["limit_window_seconds"].as_f64().unwrap_or(0.0), w));
        }
    }
    if windows.is_empty() {
        return None;
    }
    windows.sort_by(|a, b| a.0.total_cmp(&b.0));

    let pct = |w: Option<&(f64, &Value)>| {
        clamp_pct(w.map_or(0, |(_, x)| {
            x["used_percent"].as_f64().unwrap_or(0.0).round() as i64
        }))
    };
    let reset = |w: Option<&(f64, &Value)>| match w.and_then(|(_, x)| x["reset_at"].as_i64()) {
        Some(n) => Reset::Unix(n),
        None => Reset::None,
    };
    let a = windows.first()?;
    let b = windows.get(1);
    Some(Usage {
        a_pct: pct(Some(a)),
        a_reset: reset(Some(a)),
        b_pct: pct(b),
        b_reset: reset(b),
        labels: Some((window_label(a.0), b.map(|(s, _)| window_label(*s)))),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn jwt_payload_decodes() {
        // header.payload.sig — payload = {"exp":123,"account_id":"acc"}
        let payload = base64::engine::general_purpose::URL_SAFE_NO_PAD
            .encode(r#"{"exp":123,"account_id":"acc"}"#);
        let jwt = format!("h.{payload}.s");
        let p = jwt_payload(&jwt);
        assert_eq!(p["exp"].as_i64(), Some(123));
    }

    #[test]
    fn account_id_from_jwt_claim() {
        let claim = base64::engine::general_purpose::URL_SAFE_NO_PAD
            .encode(r#"{"https://api.openai.com/auth":{"chatgpt_account_id":"from-jwt"}}"#);
        let tokens = json!({"id_token": format!("h.{claim}.s")});
        assert_eq!(account_id(&tokens, &json!({})), "from-jwt");
        // tokens.account_id を優先
        let tokens2 = json!({"account_id": "direct"});
        assert_eq!(account_id(&tokens2, &json!({})), "direct");
    }

    #[test]
    fn parse_usage_weekly_by_window_seconds() {
        let v: Value = serde_json::from_str(
            r#"{"rate_limit":{
                "primary_window":{"used_percent":30,"reset_at":1000,"limit_window_seconds":18000},
                "secondary_window":{"used_percent":70,"reset_at":2000,"limit_window_seconds":604800}
            }}"#,
        )
        .unwrap();
        let u = parse_usage(&v).unwrap();
        assert_eq!(u.a_pct, 30); // current (5h window)
        assert_eq!(u.a_reset, Reset::Unix(1000));
        assert_eq!(u.b_pct, 70); // weekly (7d window)
        assert_eq!(u.b_reset, Reset::Unix(2000));
        assert_eq!(u.labels, Some(("current".into(), Some("weekly".into()))));
    }

    // 実データ回帰: free plan は 30d 枠のみ。"current 99% 28d" + 実在しない "weekly 0%" と
    // 描かれていた。
    #[test]
    fn parse_usage_single_monthly_window() {
        let v: Value = serde_json::from_str(
            r#"{"rate_limit":{
                "primary_window":{"used_percent":99,"reset_at":1789200922,"limit_window_seconds":2592000},
                "secondary_window":null
            }}"#,
        )
        .unwrap();
        let u = parse_usage(&v).unwrap();
        assert_eq!(u.a_pct, 99);
        assert_eq!(u.labels, Some(("monthly".into(), None))); // 2 行目は出さない
    }

    #[test]
    fn window_label_from_seconds() {
        assert_eq!(window_label(18000.0), "current"); // 5h
        assert_eq!(window_label(604800.0), "weekly");
        assert_eq!(window_label(2592000.0), "monthly");
        assert_eq!(window_label(3.0 * 86400.0), "3d"); // 未知の枠は日数表記
    }

    #[test]
    fn cache_roundtrip_v3() {
        let c = Codex;
        let u = Usage {
            a_pct: 30,
            a_reset: Reset::Unix(1000),
            b_pct: 70,
            b_reset: Reset::Unix(2000),
            labels: Some(("current".into(), Some("weekly".into()))),
        };
        let line = c.to_cache(&u);
        assert_eq!(line, "v3|30|70|1000|2000|current|weekly");
        assert_eq!(c.from_cache(&line), Some(u));
        assert_eq!(c.from_cache("v2|30|70|1000|2000"), None); // 旧 cache は破棄して再取得
    }

    #[test]
    fn cache_roundtrip_single_window() {
        let c = Codex;
        let u = Usage {
            a_pct: 99,
            a_reset: Reset::Unix(1789200922),
            labels: Some(("monthly".into(), None)),
            ..Usage::default()
        };
        let line = c.to_cache(&u);
        assert_eq!(line, "v3|99|0|1789200922||monthly|");
        assert_eq!(c.from_cache(&line), Some(u));
    }
}
