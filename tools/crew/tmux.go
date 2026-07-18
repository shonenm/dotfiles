package main

import (
	"os/exec"
	"strings"
)

// tmux CLI ラッパー。bash 版と同じく op ごとに tmux を fork する
// (計算でなく orchestration なので Go でもこの形が正)。

func tmuxOutput(args ...string) (string, error) {
	out, err := exec.Command("tmux", args...).Output()
	return string(out), err
}

// paneExists は #{pane_id} が全 pane に存在するか。
func paneExists(paneID string) bool {
	if paneID == "" {
		return false
	}
	out, err := tmuxOutput("list-panes", "-a", "-F", "#{pane_id}")
	if err != nil {
		return false
	}
	for _, line := range strings.Split(out, "\n") {
		if line == paneID {
			return true
		}
	}
	return false
}

// capturePaneTail は pane の表示内容の末尾 n 行。
func capturePaneTail(paneID string, n int) string {
	out, err := tmuxOutput("capture-pane", "-t", paneID, "-p")
	if err != nil {
		return ""
	}
	lines := strings.Split(strings.TrimRight(out, "\n"), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return strings.Join(lines, "\n")
}

func tmuxSendKeys(target string, keys ...string) {
	_ = exec.Command("tmux", append([]string{"send-keys", "-t", target}, keys...)...).Run()
}
