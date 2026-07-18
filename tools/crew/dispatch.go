package main

// dispatch / init は M4 で実装する。M3 では daemon loop を通すための stub。

// runInit は起動時のワーカー初期化 (M4)。stub は no-op。
func (c *Crew) runInit() int {
	// TODO(M4): tmux session/window/pane 作成 + worker spawn + launch script 生成
	return 0
}

// cmdDispatch は schedule 評価 + task dispatch (M4)。stub は no-op。
func (c *Crew) cmdDispatch(once bool) int {
	// TODO(M4): _should_dispatch / _dispatch_task / _should_restart
	return 0
}
