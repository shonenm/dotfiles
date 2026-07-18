// crew — ralph-crew の Go 置換 (Phase 2)。
// 常駐 daemon が crew.json の schedule に従い worker (claude プロセス) を
// worktree + tmux window に spawn/dispatch する自律ワーカー管理システム。
//
// subcommand: init / dispatch / daemon / status / send / restart / cleanup / teardown
// (マイルストーンごとに実装を追加)
package main

import (
	"fmt"
	"os"
)

const defaultConfig = ".claude/crew.json"

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: crew <init|dispatch|daemon|status|send|restart|cleanup|teardown>")
		os.Exit(1)
	}
	switch os.Args[1] {
	default:
		fmt.Fprintf(os.Stderr, "unknown subcommand: %s\n", os.Args[1])
		os.Exit(1)
	}
}
