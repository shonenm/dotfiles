// OAuth token ファイルの排他更新 — refresh を自前で行う provider (codex / grok) 共通。
// 同時実行は lock file で直列化し、対象ファイルは tmp + mode 継承 + rename で atomic に置換する
// (CLI 本体が読んでいる最中でも半端な JSON を見せない)。

use anyhow::{Context, Result};
use serde_json::Value;
use std::fs;
use std::io::Write;
use std::path::Path;

/// 排他 advisory lock を取る。返り値を drop するまで保持される。
pub fn lock(path: &str) -> Result<fs::File> {
    if let Some(dir) = Path::new(path).parent() {
        let _ = fs::create_dir_all(dir);
    }
    let f = fs::OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .open(path)
        .context("opening lock")?;
    f.lock().context("locking")?;
    Ok(f)
}

/// tmp に書き、元ファイルの mode を継承して rename する。
pub fn write_json(path: &str, d: &Value) -> Result<()> {
    let tmp = format!("{path}.tmp.{}", std::process::id());
    {
        let mut f = fs::File::create(&tmp).context("creating tmp")?;
        let mut s = serde_json::to_string_pretty(d)?;
        s.push('\n');
        f.write_all(s.as_bytes())?;
    }
    if let Ok(meta) = fs::metadata(path) {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(
            &tmp,
            fs::Permissions::from_mode(meta.permissions().mode() & 0o777),
        );
    }
    fs::rename(&tmp, path).context("rename tmp")?;
    Ok(())
}

/// "2026-08-15T00:11:22Z" 形式の現在時刻 (token ファイルの日時フィールド用)。
pub fn iso_now() -> String {
    iso_at(jiff::Timestamp::now())
}

/// 指定 unix 秒の ISO 表記。
pub fn iso_from_unix(secs: i64) -> String {
    match jiff::Timestamp::from_second(secs) {
        Ok(ts) => iso_at(ts),
        Err(_) => iso_now(),
    }
}

fn iso_at(ts: jiff::Timestamp) -> String {
    ts.to_string().replace("+00:00", "Z")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn iso_from_unix_is_utc_z() {
        assert_eq!(iso_from_unix(1786724860), "2026-08-14T16:27:40Z");
    }

    #[test]
    fn write_json_preserves_mode() {
        use std::os::unix::fs::PermissionsExt;
        let dir = std::env::temp_dir().join(format!("ai-usage-authstore-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("auth.json");
        let p = path.to_string_lossy().to_string();
        fs::write(&path, b"{}\n").unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).unwrap();

        write_json(&p, &serde_json::json!({"a": 1})).unwrap();

        let mode = fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600);
        assert_eq!(
            serde_json::from_str::<Value>(&fs::read_to_string(&path).unwrap()).unwrap()["a"],
            1
        );
        let _ = fs::remove_dir_all(&dir);
    }
}
