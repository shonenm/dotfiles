// TTL cache + fail backoff — bash 版の mtime ベースキャッシュと fail file を再現。
//   cache 有効 (mtime < TTL) → cache から render
//   fail file が新しい (mtime < FAIL_TTL) → placeholder (再試行しない)
//   それ以外 → fetch し、成功で cache 書込 + fail 削除 / 失敗で fail touch

use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

fn mtime_secs(path: &Path) -> Option<u64> {
    let m = fs::metadata(path).ok()?.modified().ok()?;
    Some(m.duration_since(UNIX_EPOCH).ok()?.as_secs())
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// mtime からの経過秒が ttl 未満なら true。
pub fn is_fresh(path: &Path, ttl: u64) -> bool {
    match mtime_secs(path) {
        Some(mt) => now_secs().saturating_sub(mt) < ttl,
        None => false,
    }
}

pub fn fail_path(cache: &Path) -> PathBuf {
    // bash: FAIL_FILE="${CACHE_FILE}.fail" (拡張子置換ではなく末尾追加)
    PathBuf::from(format!("{}.fail", cache.display()))
}

pub fn read_line(path: &Path) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| {
        // 先頭行のみ、末尾改行除去
        s.lines().next().unwrap_or("").to_string()
    })
}

pub fn write_line(path: &Path, line: &str) {
    if let Some(dir) = path.parent() {
        let _ = fs::create_dir_all(dir);
    }
    let _ = fs::write(path, format!("{line}\n"));
}

pub fn touch(path: &Path) {
    if let Some(dir) = path.parent() {
        let _ = fs::create_dir_all(dir);
    }
    let _ = fs::write(path, b"");
}

pub fn remove(path: &Path) {
    let _ = fs::remove_file(path);
}
