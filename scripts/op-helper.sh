#!/bin/bash
# 1Password CLI シークレット取得ヘルパー
# Usage: op-helper.sh "op://Vault/Item/field"
#
# Mac: Desktop App連携でTouch ID認証
# Linux: op signin でセッション認証

op_get() {
  local ref="$1"

  # op コマンドがなければ空を返す
  if ! command -v op &>/dev/null; then
    echo ""
    return 1
  fi

  # シークレット取得（エラーは握りつぶす）
  op read "$ref" 2>/dev/null
}

# 引数があれば実行
if [[ -n "$1" ]]; then
  op_get "$1"
fi
