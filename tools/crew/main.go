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
	sub, rest := os.Args[1], os.Args[2:]
	switch sub {
	case "status":
		os.Exit(runStatus(rest))
	case "daemon":
		os.Exit(runDaemon(rest))
	case "dispatch":
		os.Exit(runDispatch(rest))
	default:
		fmt.Fprintf(os.Stderr, "unknown subcommand: %s\n", sub)
		os.Exit(1)
	}
}

func loadCrewOrExit(configFile string) *Crew {
	crew, err := LoadCrew(configFile)
	if err != nil {
		errorf("%v", err)
		os.Exit(1)
	}
	return crew
}

func runDaemon(args []string) int {
	configFile := defaultConfig
	interval := 60
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--config":
			if i+1 < len(args) {
				configFile = args[i+1]
				i++
			}
		case "--interval":
			if i+1 < len(args) {
				fmt.Sscanf(args[i+1], "%d", &interval)
				i++
			}
		}
	}
	return loadCrewOrExit(configFile).cmdDaemon(interval)
}

func runDispatch(args []string) int {
	configFile := defaultConfig
	once := false
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--config":
			if i+1 < len(args) {
				configFile = args[i+1]
				i++
			}
		case "--once":
			once = true
		}
	}
	return loadCrewOrExit(configFile).cmdDispatch(once)
}

// parseConfigFlag は --config <path> / --json を拾う共通ヘルパ。
func parseConfigFlag(args []string) (configFile string, jsonMode bool) {
	configFile = defaultConfig
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--config":
			if i+1 < len(args) {
				configFile = args[i+1]
				i++
			}
		case "--json":
			jsonMode = true
		}
	}
	return
}

func runStatus(args []string) int {
	configFile, jsonMode := parseConfigFlag(args)
	crew, err := LoadCrew(configFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		return 1
	}
	if err := crew.cmdStatus(jsonMode); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		return 1
	}
	return 0
}
