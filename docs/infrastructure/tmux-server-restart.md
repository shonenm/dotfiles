# tmux server 再起動 & 復元 runbook

長寿命 tmux server が重くなった時の再起動判断と、AI と協力してセッション・agent を
復元する手順。実測は 2026-07-18 の ailab(chronos.lab) 対応に基づく。

## いつ再起動すべきか

### 症状
- 全 tmux 操作(pane/window/session 切替、prefix コマンド)が一様に遅い(0.2〜1s)。
  稼働中 agent の数とは無関係。数十日の連続稼働 + 多 pane(数十〜)で顕在化。

### 根本原因
長寿命サーバはアドレス空間の断片化(VMA 増加)で `fork()` が肥大する
(fresh ~5ms → 肥大 ~250ms、実測 50 倍)。tmux は単一イベントループで、
status-right の `#()` や session 切替 hook が redraw 毎に fork するため、
1 fork の遅延がそのまま全操作の体感遅延になる。

### 診断コマンド
```bash
# fork コスト (fresh ~0.05s / 肥大 >1.5s)
time bash -c 'for i in $(seq 10); do tmux run-shell true; done'

# server RSS (数百MB〜1GB で要注意)
ps -o rss= -p "$(tmux display-message -p '#{pid}')"

# 孤立 server と比較 (memory: project_tmux_fork_latency)
tmux -L bench new-session -d
time tmux -L bench run-shell true
tmux -L bench kill-server
```

### やっても効かない対策(回避)
- `history-limit` 縮小 → 既存 pane に非遡及。新規 pane のみ。
- `clear-history` → glibc がヒープを OS に返さず RSS 減らない。
- `malloc_trim` → RSS は少し減るが VMA 数は不変 = fork コスト据え置き。

→ 断片化のリセット = **server 再起動が唯一の根治**。

### 再起動で直らないもの
同一 session 内 pane 切替の体感遅延が主なら、それは server ではなく
**network(VPN/WiFi + plain SSH の RTT/ジッタ)**。再起動では変わらない。
接続品質を確認し、必要なら有線化やSSH transport自体の見直しを行う。

## 復元の土台: resurrect / continuum

continuum が 15 分毎に session/window/pane 構成 + レイアウト + cwd を
`~/.local/share/tmux/resurrect/` に自動保存している(`@continuum-restore on`)。
再起動時のレイアウト復元はこれで自動。ただし **復元されるのは shell だけ**で、
agent(claude/pi)は whitelist 外のため手動再起動が要る。

## 再起動 & 復元手順(AI と協力)

### 1. 事前採取(kill 前・read-only)
```bash
# 稼働中 agent(pi/claude) pane の特定
tmux list-panes -a -F '#{session_name}|#{window_index}.#{pane_index}|#{pane_current_command}|#{pane_current_path}'
# レイアウト backup
tmux list-windows -a -F '#{session_name}|#{window_layout}' > ~/.cache/tmux-restore/layouts.txt
# 最新 save を強制
~/.tmux/plugins/tmux-resurrect/scripts/save.sh
```
- claude resume ID: `~/.claude/projects/<cwd-escaped>/*.jsonl` の mtime 最新から
  pane 数分。同一 cwd に複数 claude があるなら最新 N 個を明示 `--resume <id>` で対応。
- pi は `pi --continue`(cwd の最新セッション自動再開)で足りる。ID 不要。

### 2. 再起動 — **必ず rcon 経由で起動する**
> 手動 `tmux new-session` で起動してはいけない。非対話 env で起動すると:
> - `SHELL=bash` + 最小 PATH になり pane が nix/pixi zsh でなく bash に。
>   claude は zsh 関数(`.zshrc.common`)、pi は pixi/mise の PATH 依存なので起動不可。
> - server env に `~/.pixi/bin`(zsh の場所)が無く、display-popup(prefix g/G/Q 等)が
>   `zsh` を見失い全 popup が無反応になる。
>
> `rcon ailab`(host target)は `SHELL=zsh` + フル PATH + 正しい `default-command`
> (`tmux-default-shell`)を設定してから起動するため、これらを全て回避できる。

```bash
tmux kill-server        # 全 session 終了・断片化解放
rcon ailab              # 正しい env で新サーバ起動 + attach
```

### 3. 復元
1. attach 状態(client あり = TTY)で作業する。レイアウトが端末サイズへ再展開される。
2. continuum が自動復元しない場合のみ明示実行:
   `~/.tmux/plugins/tmux-resurrect/scripts/restore.sh`
3. agent 再起動 — 各 agent pane へ送信:
   - claude: `claude --resume <id>`
   - pi: `pi --continue`
4. サイドバー: 各 session で Prefix B。
   (または左端 pane で `exec ~/dotfiles/scripts/tmux-agent-sidebar.sh run` +
   `tmux set-option -w @agent_sidebar_pane <pane_id>` で in-place 復活)

### 4. 落とし穴(2026-07-18 に踏んだもの)
- **headless での `kill-pane` や hung プロセス kill は "server exited unexpectedly"
  クラッシュを誘発しやすい**(ghostty 絡みの既知不安定性)。pane 操作は attach 後に。
- クラッシュしても resurrect save から復旧できる。慌てず `restore.sh`。
- restore は 1 session に余分 pane を足すことがある(artifact) → prefix-x で閉じる。
- `@rcon-*` session option は resurrect で復元されない(host session なら実害なし)。
- 手動起動してしまった後の応急: `tmux set-environment -g PATH "$(bash -lc 'echo $PATH')"`
  で server env の PATH を補い popup を復活(本来は rcon 起動で不要)。

## AI に依頼する時の指示例
> ailab の tmux server が重い。fork レイテンシを診断して、重ければ resurrect で
> レイアウト復元 + agent(claude は --resume、pi は --continue)を再起動して。
> 起動は必ず rcon 経由。稼働中 agent を kill する前に resume ID を採取しておいて。

## 実測(参考, 2026-07-18 ailab)
| 指標 | before | after |
|---|---|---|
| fork コスト | 154ms | 8ms |
| server RSS | 1137MB | 23MB |
| session / agent | 14 / 15 | 14 / 15(全復元) |

関連: [rcon.md](./rcon.md)、memory `project_tmux_fork_latency`
