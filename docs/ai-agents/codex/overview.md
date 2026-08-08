# Codex CLI

> **由来:** **Upstream** Codex CLI・native Web search・subagents / **Configuration** config・global instructions・shared skills・hooks（[区分](../../provenance.md#区分)）

Codexはrepository内の自律作業と、PiからのWeb検索fallback・second opinionに使う。Pi側へCodex native機能を再実装せず、Codexのsandbox、Web検索、goals、memories、multi-agentを利用する。

## 正本

| 対象 | 正本 |
|---|---|
| runtime config | `templates/codex-config.toml`（`install.sh`が`__HOME__`を展開） |
| global instructions | `common/codex/.codex/AGENTS.md` |
| shared skills | `common/agent/.config/agent/skills/` |
| lifecycle hooks | `templates/codex-config.toml` |

`common/codex/.codex/config.toml`はStow単体利用時の基本設定であり、通常の`install.sh`ではtemplateから生成した設定がruntimeの正本となる。

## 主要設定

- `model_reasoning_effort = "medium"`: 対話速度を保ちつつ、`low`で起きやすい調査精度低下を避ける。
- `project_doc_fallback_filenames = ["CLAUDE.md"]`: `AGENTS.md`がないprojectでも既存のproject規則を読む。
- `service_tier = "fast"`: 対話latencyを優先する。
- `goals` / `memories` / `multi_agent`: Codex native機能を使う。
- `approval_policy = "on-request"` + `repo-autonomous`: repository内は自律実行し、範囲外だけ確認する。

## Shared skills

`install.sh`は`common/agent/.config/agent/skills/*`を`~/.codex/skills/`へsymlinkする。既存の非symlink skillは上書きしない。research skillはruntimeを判別し、Codexではnative search、Piでは`web_*` toolsを使う。

## PiからのWeb検索fallback

Piの`web_search` backendが利用不能な場合だけ、共有`deep-research` skillに従って検索を委譲する。

```bash
codex --search exec --skip-git-repo-check --ephemeral \
  -c model_reasoning_effort=medium \
  "Search for <topic>. Return primary-source URLs and exact supporting quotes."
```

repositoryへの編集は親sessionだけが行い、Codexの検索結果はURLまたは原典で再確認する。`--search`はnative Web検索、`multi_agent`はnative subagentの設定として独立に管理する。

## 検証

```bash
scripts/test-codex-config.sh
codex features list
```
