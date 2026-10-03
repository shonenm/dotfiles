# pi MCP Layer

> **由来:** **Upstream** pi標準MCP・各MCP server / **Plugin** pi-permission-system / **Configuration** 共有MCP定義・権限設定・symlink（[区分](../../provenance.md#区分)）

pi 1.0.0の `builtin:mcp` を使う。独自の `mcp-gateway.ts` は廃止し、`/mcp` は標準server managerが担当する。

## 設定

`common/pi/.pi/agent/mcp.json` は共有正本 `common/agent/.config/agent/mcp.json` への相対symlink。`install.sh` のGNU Stow処理により `~/.pi/agent/mcp.json` へ配置される。macOS / Linux / no-sudoで同じ構成を使う。

読み込み順序:

1. `~/.pi/agent/mcp.json` — 共有設定と同じ内容
2. `<project>/.pi/mcp.json` — trusted projectだけ。同名serverはglobal設定を置換

旧gatewayが読んでいた `<project>/.mcp.json` は標準MCPでは読まれない。project固有serverは `.pi/mcp.json` へ移す。

Claude Codeは `common/claude/.config/claude/mcp.json` を別の正本とし、`install.sh` が登録する。Cursorは共有設定から `~/.cursor/mcp.json` を生成する。

```json
{
  "mcpServers": {
    "server-name": {
      "type": "stdio",
      "command": "server-command",
      "args": [],
      "description": "purpose",
      "enabled": true
    }
  }
}
```

stdioとStreamable HTTPはpi標準実装が扱う。独自transportは追加しない。secretはファイルへ直書きせず、標準の `${NAME}` 参照を使う。

`/mcp` や `pi mcp add/remove` によるglobal設定の変更はsymlink先の共有正本にも反映される。piだけの差分はproject側へ置く。

## Toolと権限

tool名は `mcp__<server>__<tool>`。既定のexposureは `codemode` で、toolを直接modelへ宣言せず、`searchTools()` / `describeNamespace()` で発見して呼ぶ。`deferred` は `tool_search` で発見し、`direct` は常時宣言する。

```text
LLM
  → codemode / tool_search / direct MCP tool
  → piのtool pipeline
  → pi-permission-system
  → 標準MCP client
  → upstream MCP
  → 標準の結果処理
  → model
```

codemodeからの呼び出しも `tool_call` / `tool_result` を通る。`pi-permissions.jsonc` の `tools["mcp__*"] = "ask"` で通常モードの確認を維持する。YOLO modeでは自動許可する。`pi mcp` のshell commandはsession extensionを読み込まないため、この権限gateを通らない。

## 結果とログ

- 20 KBを超えるtext結果は標準処理で中間を省略し、完全な結果を一時fileへ保存する。
- codemodeはMCPの完全な結果を受け取る。必要な部分だけ返すことでmodelへ渡す量を減らせる。
- serverのlogging通知は `~/.pi/agent/mcp.log` へ記録する。
- 旧gatewayの独自shaper、`maxResultSize`、audit / stats / overflow保存は廃止。標準MCPは既存設定の `shapes` / `maxResultSize` を利用しない。過去の保存データは削除しない。

## 確認と反映

```bash
scripts/test-pi-mcp.sh    # 隔離serverでconfig / 権限 / 接続を検証
pi --version             # 1.0.0
pi mcp list              # 有効serverへ接続して状態とtool一覧を確認
```

旧gatewayから標準MCPへ移行する既存環境では、共有設定が存在しても `~/.pi/agent/mcp.json` がなければserverは読み込まれない。dotfilesの更新や `/reload` だけでは新しいlinkは作られない。再インストールは不要で、まず既存の配置を確認する。

```bash
ls -ld ~/.pi/agent/mcp.json
```

ファイルもsymlinkも存在しない場合に限り、共有正本へのlinkを作る。既存の設定や壊れたsymlinkがある場合は上書きせず、その配置を確認する。

```bash
if [ ! -e "$HOME/.pi/agent/mcp.json" ] && [ ! -L "$HOME/.pi/agent/mcp.json" ]; then
  mkdir -p "$HOME/.pi/agent"
  ln -s "$HOME/.config/agent/mcp.json" "$HOME/.pi/agent/mcp.json"
fi
pi mcp list
```

`No MCP servers configured` は接続失敗ではなく、server設定が読み込まれていない状態。`pi mcp list` でserver名・接続状態・tool数を確認した後、実行中のsessionで `/reload` またはpiを再起動する。link復元前の `/reload` では解消しない。

`pi mcp list` は接続に失敗するとexit 1。接続先の認証や起動エラーは `/mcp` で確認する。

MCP serverの選択には共有skill `mcp-research` を使う。正本は `common/agent/.config/agent/skills/mcp-research/SKILL.md`。

関連: [共有設定レイヤー](agent-layer.md)
