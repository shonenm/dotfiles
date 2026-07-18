// ステータス表示は全て stderr へ (data=stdout の契約を守るため)。
// bash 版 wt_success/error/info と同じ色プレフィックス。

pub fn success(msg: &str) {
    eprintln!("\x1b[0;32mok\x1b[0m {msg}");
}

pub fn error(msg: &str) {
    eprintln!("\x1b[0;31merror\x1b[0m {msg}");
}

pub fn info(msg: &str) {
    eprintln!("\x1b[0;36minfo\x1b[0m {msg}");
}
