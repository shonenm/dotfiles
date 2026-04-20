#!/usr/bin/env bash
# UserPromptSubmit hook: 初回ユーザープロンプトでセッション名を自動生成する。
# プロンプト先頭行を切り出して sessionTitle に設定。一度設定したら再実行しない。
# zsh ラッパー側で付与する --name (ブランチ名) を、初回プロンプト後にタスク内容で上書きする役割。

set -euo pipefail

# jq 不在ならフェイルオープン
if ! command -v jq &>/dev/null; then
  exit 0
fi

input="$(cat)"
session_id="$(jq -r '.session_id // ""' <<<"$input")"
[[ -z "$session_id" ]] && exit 0

state_dir="${HOME}/.claude/state"
marker="${state_dir}/session-titled-${session_id}"
[[ -f "$marker" ]] && exit 0

prompt="$(jq -r '.prompt // ""' <<<"$input")"
[[ -z "$prompt" ]] && exit 0

output_json="$(jq -n --arg prompt "$prompt" '
  def clean: split("\n")[0] | sub("^\\s+"; "") | sub("\\s+$"; "");
  def maybe_truncate: if length > 50 then .[0:50] + "…" else . end;
  ($prompt | clean) as $line
  | if ($line | length) >= 5 and (($line | startswith("/")) | not) then
      { hookSpecificOutput: { hookEventName: "UserPromptSubmit", sessionTitle: ($line | maybe_truncate) } }
    else
      empty
    end
')"

if [[ -n "$output_json" ]]; then
  mkdir -p "$state_dir"
  touch "$marker"
  printf '%s' "$output_json"
fi
