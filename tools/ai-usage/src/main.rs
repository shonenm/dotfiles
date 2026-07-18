// ai-usage — tmux status-right の usage widget を 1 binary に統合。
//   usage: ai-usage <claude|codex|gemini|cursor>
//   出力は bash 版と bit 互換の US(0x1f) 区切りレコード。失敗しても exit 0 で
//   placeholder を出し、呼び出し側 (tmux/sidebar) を絶対に壊さない (fail-open)。

mod cache;
mod http;
mod providers;
mod render;

use providers::{Provider, Usage};
use std::process::ExitCode;

fn provider_for(name: &str) -> Option<Box<dyn Provider>> {
    match name {
        "claude" => Some(Box::new(providers::claude::Claude)),
        "codex" => Some(Box::new(providers::codex::Codex)),
        "gemini" => Some(Box::new(providers::gemini::Gemini)),
        "cursor" => Some(Box::new(providers::cursor::Cursor)),
        _ => None,
    }
}

fn print_usage(p: &dyn Provider, u: &Usage) {
    let (la, lb) = p.labels();
    println!("{}", render::record(p.icon(), la, u.a_pct, &u.a_reset));
    println!("{}", render::record(p.icon(), lb, u.b_pct, &u.b_reset));
}

fn print_na(p: &dyn Provider) {
    println!("{}", render::na_line(p.icon()));
}

fn run(p: &dyn Provider) {
    let cache_path = p.cache_path();
    let fail = cache::fail_path(&cache_path);

    // 1. cache 有効なら cache から
    if cache::is_fresh(&cache_path, p.cache_ttl())
        && let Some(line) = cache::read_line(&cache_path)
        && let Some(u) = p.from_cache(&line)
    {
        print_usage(p, &u);
        return;
    }

    // 2. 直近失敗のバックオフ中なら再試行せず placeholder
    if cache::is_fresh(&fail, p.fail_ttl()) {
        print_na(p);
        return;
    }

    // 3. 取得
    match p.fetch() {
        Ok(u) => {
            cache::write_line(&cache_path, &p.to_cache(&u));
            cache::remove(&fail);
            print_usage(p, &u);
        }
        Err(_) => {
            cache::touch(&fail);
            print_na(p);
        }
    }
}

fn main() -> ExitCode {
    let name = std::env::args().nth(1).unwrap_or_default();
    match provider_for(&name) {
        Some(p) => {
            run(&*p);
            ExitCode::SUCCESS
        }
        None => {
            eprintln!("usage: ai-usage <claude|codex|gemini|cursor>");
            ExitCode::FAILURE
        }
    }
}
