// ureq エージェント（全プロバイダ共通、5s グローバルタイムアウト = bash の curl --max-time 5）。

use std::time::Duration;

pub fn agent() -> ureq::Agent {
    let config = ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(5)))
        .build();
    ureq::Agent::new_with_config(config)
}
