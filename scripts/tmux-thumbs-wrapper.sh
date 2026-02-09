#!/bin/bash
# tmux-thumbs wrapper - thumbs を正しく起動するラッパー

THUMBS_BIN="$HOME/.tmux/plugins/tmux-thumbs/target/release/thumbs"
TMP_FILE="/tmp/thumbs-last-$$"

# 現在のペイン・ウィンドウ情報を取得
PANE_ID=$(tmux display -p '#{pane_id}')
WINDOW_ID=$(tmux display -p '#{window_id}')

# ペイン内容をキャプチャ
CAPTURE_FILE=$(mktemp)
tmux capture-pane -J -t "$PANE_ID" -p > "$CAPTURE_FILE"

# thumbs を新しいウィンドウで実行し、結果を処理して元のウィンドウに戻る
tmux new-window -n "[thumbs]" "\
  cat '$CAPTURE_FILE' | '$THUMBS_BIN' -f '%U:%H' -t '$TMP_FILE'; \
  rm -f '$CAPTURE_FILE'; \
  if [ -f '$TMP_FILE' ]; then \
    RESULT=\$(cat '$TMP_FILE'); \
    UPCASE=\$(echo \"\$RESULT\" | cut -d: -f1); \
    TEXT=\$(echo \"\$RESULT\" | cut -d: -f2-); \
    rm -f '$TMP_FILE'; \
    if [ \"\$UPCASE\" = 'true' ]; then \
      tmux display-message -d 800 \"Opening: \$TEXT\"; \
      open \"\$TEXT\" 2>/dev/null || \${EDITOR:-nvim} \"\$TEXT\"; \
    else \
      echo -n \"\$TEXT\" | pbcopy; \
      tmux display-message -d 800 \"Copied: \$TEXT\"; \
    fi; \
  fi; \
  tmux select-window -t '$WINDOW_ID'"

exit 0
