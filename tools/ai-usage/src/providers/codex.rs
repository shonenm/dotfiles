// Codex (OpenAI) usage — ~/.codex/auth.json の OAuth token。Codex CLI と同じ
// refresh-token flow を持つ (期限切れ access_token を使うと usage が 401 で落ちる)。
// refresh は fcntl 排他ロック下で行い、auth.json を tmp+chmod+rename で atomic 更新する。

use super::{Provider, Reset, Usage, clamp_pct};
use crate::http;
use anyhow::{Context, Result, anyhow};
use base64::Engine;
use serde_json::{Value, json};
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

const WEEK: f64 = 7.0 * 24.0 * 60.0 * 60.0;

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
    /// 戻り値: (access_token, account_id)。
    fn refresh_auth(&self) -> Result<(String, String)> {
        let path = auth_file();
        let lock_path = format!("{}.refresh.lock", cache_base());
        if let Some(dir) = std::path::Path::new(&lock_path).parent() {
            let _ = fs::create_dir_all(dir);
        }
        let lock = fs::OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .open(&lock_path)
            .context("opening lock")?;
        lock.lock().context("locking")?; // std File::lock (排他, advisory) — drop で解放

        let body = fs::read_to_string(&path).context("reading auth.json")?;
        let mut d: Value = serde_json::from_str(&body).context("parsing auth.json")?;
        let access = d["tokens"]["access_token"].as_str().unwrap_or("").to_string();
        let acc = account_id(&d["tokens"], &d);
        let exp = jwt_payload(&access)["exp"].as_i64().unwrap_or(0);
        if !access.is_empty() && exp > now_secs() + 60 {
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
        d["last_refresh"] = json!(iso_now());

        write_atomic(&path, &d)?;
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

fn iso_now() -> String {
    jiff::Timestamp::now()
        .to_string()
        .replace("+00:00", "Z")
}

/// tmp に書き、元ファイルの mode を継承して rename (bash の atomic write と同じ)。
fn write_atomic(path: &str, d: &Value) -> Result<()> {
    let tmp = format!("{path}.tmp.{}", std::process::id());
    {
        let mut f = fs::File::create(&tmp).context("creating tmp")?;
        let mut s = serde_json::to_string_pretty(d)?;
        s.push('\n');
        f.write_all(s.as_bytes())?;
    }
    if let Ok(meta) = fs::metadata(path) {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&tmp, fs::Permissions::from_mode(meta.permissions().mode() & 0o777));
    }
    fs::rename(&tmp, path).context("rename tmp")?;
    Ok(())
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
            let (t, a) = self.refresh_auth()?;
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
        let mut raw = self.fetch_usage(&token, &acc);
        if raw.is_none() && !auth.refresh_token.is_empty() && !refresh_attempted {
            let (t, a) = self.refresh_auth()?;
            if !t.is_empty() {
                raw = self.fetch_usage(&t, &a);
            }
        }
        let raw = raw.ok_or_else(|| anyhow!("usage fetch failed"))?;
        let v: Value = serde_json::from_str(&raw).context("parsing usage json")?;
        parse_usage(&v).ok_or_else(|| anyhow!("no usable windows"))
    }

    fn to_cache(&self, u: &Usage) -> String {
        // bash: "v2|{s}|{w}|{current_resets_unix}|{weekly_resets_unix}"
        format!(
            "v2|{}|{}|{}|{}",
            u.a_pct,
            u.b_pct,
            u.a_reset.to_field(),
            u.b_reset.to_field()
        )
    }

    fn from_cache(&self, line: &str) -> Option<Usage> {
        let f: Vec<&str> = line.split('|').collect();
        if f.first() != Some(&"v2") {
            return None;
        }
        let a_pct: i64 = f.get(1)?.parse().ok()?;
        let b_pct: i64 = f.get(2)?.parse().ok()?;
        let unix = |i: usize| match f.get(i).and_then(|s| s.parse::<i64>().ok()) {
            Some(n) => Reset::Unix(n),
            None => Reset::None,
        };
        Some(Usage {
            a_pct,
            a_reset: unix(3),
            b_pct,
            b_reset: unix(4),
        })
    }
}

/// rate_limit の primary/secondary window から weekly (≈7d) を判別し current/weekly に。
fn parse_usage(v: &Value) -> Option<Usage> {
    let rl = &v["rate_limit"];
    let mut windows: Vec<&Value> = Vec::new();
    for k in ["primary_window", "secondary_window"] {
        let w = &rl[k];
        if w.is_object() && !w.as_object().unwrap().is_empty() {
            windows.push(w);
        }
    }
    if windows.is_empty() {
        return None;
    }

    let is_weekly = |w: &Value| {
        let sec = w["limit_window_seconds"].as_f64().unwrap_or(0.0);
        (WEEK * 0.95..=WEEK * 1.05).contains(&sec)
    };
    let weekly = windows.iter().find(|w| is_weekly(w)).copied();
    let mut current = windows.iter().find(|w| !is_weekly(w)).copied();
    // 未知 payload では primary=current, secondary=weekly にフォールバック。
    if current.is_none() {
        current = windows.first().copied();
    }
    let weekly = weekly.or_else(|| windows.get(1).copied());

    let pct = |w: Option<&Value>| clamp_pct(w.map_or(0, |x| x["used_percent"].as_f64().unwrap_or(0.0).round() as i64));
    let reset = |w: Option<&Value>| match w.and_then(|x| x["reset_at"].as_i64()) {
        Some(n) => Reset::Unix(n),
        None => Reset::None,
    };
    Some(Usage {
        a_pct: pct(current),
        a_reset: reset(current),
        b_pct: pct(weekly),
        b_reset: reset(weekly),
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
    }

    #[test]
    fn cache_roundtrip_v2() {
        let c = Codex;
        let u = Usage {
            a_pct: 30,
            a_reset: Reset::Unix(1000),
            b_pct: 70,
            b_reset: Reset::Unix(2000),
        };
        let line = c.to_cache(&u);
        assert_eq!(line, "v2|30|70|1000|2000");
        assert_eq!(c.from_cache(&line), Some(u));
        assert_eq!(c.from_cache("30|70|1000|2000"), None); // v2 prefix 必須
    }
}
