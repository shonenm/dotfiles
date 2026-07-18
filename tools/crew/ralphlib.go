package main

import (
	"os"
	"os/exec"
	"path/filepath"
)

// ralph-lib.sh への shell-out。Claude 所有スキーマ (permissions / ~/.claude.json trust)
// の jq 操作は bash に温存し、Go は薄い境界だけ持つ (監査の net-regression 回避)。

// ralphLibPath は ralph-lib.sh の場所を解決する。
// 優先: 環境変数 RALPH_LIB → crew binary と同じ dir → PATH の scripts。
func ralphLibPath() string {
	if p := os.Getenv("RALPH_LIB"); p != "" {
		return p
	}
	// dotfiles の scripts/ を想定 (crew は ~/.local/bin、ralph-lib.sh は ~/dotfiles/scripts)。
	if home := os.Getenv("HOME"); home != "" {
		cand := filepath.Join(home, "dotfiles", "scripts", "ralph-lib.sh")
		if _, err := os.Stat(cand); err == nil {
			return cand
		}
	}
	return "ralph-lib.sh" // PATH 頼み
}

func runRalphLib(args ...string) error {
	cmd := exec.Command("bash", append([]string{ralphLibPath()}, args...)...)
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	return cmd.Run()
}

// setupWorkerSettings は権限調整 (has_fix) + settings.local.json 生成を bash に委譲。
func (c *Crew) setupWorkerSettings(projectDir, permissionsJSON, hookJSON string, hasFix bool) error {
	fix := "0"
	if hasFix {
		fix = "1"
	}
	return runRalphLib("setup-worker", projectDir, permissionsJSON, hookJSON, fix)
}

// preacceptTrust は ~/.claude.json の trust 事前承認を bash に委譲。
func (c *Crew) preacceptTrust(workerCwd string) error {
	return runRalphLib("preaccept-trust", workerCwd)
}
