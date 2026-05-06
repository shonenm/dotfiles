# Clipboard 統合

tmux popup (`display-popup -E`) 内の copy 操作を host (mac) clipboard に
同期させる仕組み。tmux 3.6 の既知挙動として popup pty からの OSC52 escape
sequence は outer terminal に転送されないため、OSC52 に依存しない経路を
用意する。

## 構成要素

| 要素 | 役割 | 配置 |
|------|------|------|
| `scripts/clipboard-copy` | OS判定 wrapper。stdin → clipboard | host / remote 両方 |
| `scripts/clipboard-relay-server` | `nc -l 127.0.0.1 2489` ループで受信し pbcopy | host のみ |
| `templates/com.user.clipboard-relay.plist` | mac で relay-server を常駐 | host のみ |
| `tmux.conf` | copy-mode-vi `y` / mouse drag を `copy-pipe-and-cancel` で wrapper に流す | host / remote 両方 |
| `lazygit/config.yml` | `os.copyToClipboardCmd` で wrapper を呼ぶ | host / remote 両方 |
| `mac/ssh/config` | `RemoteForward 2489` で remote → mac 接続を逆 forward | host のみ |

## 解決順序 (clipboard-copy 内)

1. macOS → `pbcopy`
2. SSH session → `cat >/dev/tcp/127.0.0.1/2489` (bash builtin、netcat 不要)
3. Wayland → `wl-copy`
4. X11 → `xclip` / `xsel`
5. fallback OSC52 (popup では効かないが pane では機能)

remote → mac の経路:

```
[remote tmux popup] → clipboard-copy → /dev/tcp/127.0.0.1:2489
                                            ↓ (SSH RemoteForward)
                                       mac:127.0.0.1:2489
                                            ↓ (nc accept)
                                       clipboard-relay-server
                                            ↓
                                          pbcopy
```

## セットアップ

### macOS (host)

```bash
cd ~/dotfiles && ./scripts/mac.sh
# install_clipboard_relay が以下を実行:
#   - templates/com.user.clipboard-relay.plist を ~/Library/LaunchAgents/ に展開
#   - launchctl bootstrap で常駐起動 (port 2489 listen)
```

確認:

```bash
lsof -i :2489                 # nc がリッスン中か
launchctl list | grep clipboard-relay
echo hello | nc 127.0.0.1 2489 && pbpaste   # → "hello"
```

### Linux remote

```bash
cd ~/dotfiles && ./install.sh
# clipboard-copy wrapper が stow されるだけ。
# 追加の binary は不要 (bash builtin /dev/tcp 利用)。
```

### SSH 接続

`mac/ssh/.ssh/config` に `Host *` ブロックで `RemoteForward 2489 localhost:2489`
を設定済み。任意のリモートに ssh するだけで自動的に逆フォワードされる。

確認:

```bash
# mac → remote
ssh user@remote
# remote 側で:
ss -tln | grep 2489    # 2489 が remote 上で listen 中
echo hello > /dev/tcp/127.0.0.1/2489
# mac 側で確認:
pbpaste                # → "hello"
```

## tmux popup での挙動

| 場面 | 経路 | 結果 |
|------|------|------|
| 通常 pane で `y` (mac) | wrapper → pbcopy | host clipboard |
| 通常 pane で `y` (remote) | wrapper → /dev/tcp:2489 → mac relay → pbcopy | host clipboard |
| popup 内 lazygit の copy (mac) | lazygit → wrapper → pbcopy | host clipboard |
| popup 内 lazygit の copy (remote) | lazygit → wrapper → /dev/tcp:2489 → mac | host clipboard |
| popup 内 nested tmux scratch の `y` (mac) | inner tmux → wrapper → pbcopy | host clipboard |
| popup 内 nested tmux scratch の `y` (remote) | inner tmux → wrapper → /dev/tcp:2489 → mac | host clipboard |

## トラブルシューティング

- mac で `pbpaste` が変わらない:
  - `launchctl list com.user.clipboard-relay` で常駐確認
  - `tail -f /tmp/clipboard-relay.err`
  - `lsof -i :2489` で nc が listen しているか
- remote で `> /dev/tcp/127.0.0.1/2489` が `Connection refused`:
  - SSH の `RemoteForward 2489` が効いていない (sshd `AllowTcpForwarding yes` 必要)
  - 既存 SSH セッションは `RemoteForward` 追加後に再接続が必要
- lazygit でコピーされない:
  - `~/.config/lazygit/config.yml` の `os.copyToClipboardCmd` が wrapper になっているか確認
- tmux で `y` が効かない:
  - `tmux list-keys -T copy-mode-vi | grep ' y '` で binding 確認
  - tmux server が落ちていれば `tmux new` で再起動
