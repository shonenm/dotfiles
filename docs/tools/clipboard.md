# Clipboard 統合

tmux popup (`display-popup -E`) 内の copy 操作を host (mac) clipboard に
同期させる仕組み。tmux 3.6 の既知挙動として popup pty からの OSC52 escape
sequence は outer terminal に転送されないため、OSC52 に依存しない経路を
用意する。

## 構成要素

| 要素 | 役割 | 配置 |
|------|------|------|
| `scripts/clipboard-copy` | OS判定 wrapper。stdin → clipboard | host / remote 両方 |
| `tmux.conf` | copy-mode-vi `y` / mouse drag を `copy-pipe-and-cancel` で wrapper に流す | host / remote 両方 |
| `lazygit/config.yml` | `os.copyToClipboardCmd` で wrapper を呼ぶ | host / remote 両方 |
| `lemonade` | remote 側 → host 側 clipboard へ TCP relay | mac (server) + linux remote (client) |
| `mac/ssh/config` | `RemoteForward 2489` で remote → mac 接続を逆 forward | host のみ |
| `templates/com.user.lemonade.plist` | mac 側で lemonade-server 常駐 | host のみ |

## 解決順序 (clipboard-copy 内)

1. macOS → `pbcopy`
2. SSH session かつ `lemonade` あり → `lemonade copy`
3. Wayland → `wl-copy`
4. X11 → `xclip` / `xsel`
5. fallback OSC52 (popup では効かないが pane では機能)

## セットアップ

### macOS (host)

```bash
cd ~/dotfiles && ./scripts/mac.sh
# install_lemonade が以下を実行:
#   - lemonade を ~/.local/bin に配置
#   - launchd で com.user.lemonade を bootstrap (port 2489 listen)
```

確認:

```bash
lsof -i :2489          # lemonade-server がリッスン中か
launchctl list | grep lemonade
```

### Linux remote

```bash
cd ~/dotfiles && ./install.sh
# tools.linux.bash に lemonade 登録済み (LINUX_TOOL_ORDER) →
# github_release tarball から ~/.local/bin/lemonade に install。
# 注: x86_64 のみ自動 install (upstream に linux_arm64 binary なし)。
#     arm64 環境では `go install github.com/lemonade-command/lemonade@latest`
#     で self-build してください。
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
echo hello | lemonade copy
# mac 側で確認:
pbpaste                # → "hello"
```

## tmux popup での挙動

| 場面 | 経路 | 結果 |
|------|------|------|
| 通常 pane で `y` (mac) | wrapper → pbcopy | host clipboard |
| 通常 pane で `y` (remote) | wrapper → lemonade copy → 2489 → mac pbcopy | host clipboard |
| popup 内 lazygit の copy (mac) | lazygit → wrapper → pbcopy | host clipboard |
| popup 内 lazygit の copy (remote) | lazygit → wrapper → lemonade copy → mac | host clipboard |
| popup 内 nested tmux scratch の `y` (mac) | inner tmux → wrapper → pbcopy | host clipboard |
| popup 内 nested tmux scratch の `y` (remote) | inner tmux → wrapper → lemonade copy → mac | host clipboard |

## トラブルシューティング

- mac で `pbpaste` が変わらない → `launchctl list com.user.lemonade` 確認、
  `tail -f /tmp/lemonade.err`
- remote で `lemonade copy` が `connection refused` → SSH の `-R 2489` が効いて
  いない (sshd `AllowTcpForwarding yes` 必要)
- lazygit でコピーされない → `~/.config/lazygit/config.yml` の
  `os.copyToClipboardCmd` が wrapper になっているか確認
