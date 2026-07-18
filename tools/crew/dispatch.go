package main

import (
	"embed"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/template"
	"time"
)

//go:embed templates/*.md.tmpl
var promptTemplates embed.FS

var tmpl = template.Must(template.ParseFS(promptTemplates, "templates/*.md.tmpl"))

type promptData struct {
	TaskID, Prompt, Branch, DefaultBranch, WorkerID string
}

// renderPrompt は action に応じた prompt 本文を生成 (bash _dispatch_task の heredoc 群)。
func renderPrompt(action string, d promptData) (string, error) {
	name := action + ".md.tmpl"
	switch action {
	case "none", "issue-only":
	default:
		name = "fix.md.tmpl"
	}
	var sb strings.Builder
	if err := tmpl.ExecuteTemplate(&sb, name, d); err != nil {
		return "", err
	}
	return sb.String(), nil
}

// dispatchTask は bash _dispatch_task の移植。prompt 生成 → status=running →
// launch script で pane respawn → TUI 待ち → send-keys で prompt 注入 → 記録。
func (c *Crew) dispatchTask(paneID, taskID, prompt, workerID, action string) error {
	defaultBranch := c.detectDefaultBranch()
	branch := fmt.Sprintf("crew/%s-%s", workerID, time.Now().Format("200601021504"))

	body, err := renderPrompt(action, promptData{
		TaskID: taskID, Prompt: prompt, Branch: branch,
		DefaultBranch: defaultBranch, WorkerID: workerID,
	})
	if err != nil {
		return err
	}
	promptFile := filepath.Join(c.StateDir, "prompts", taskID+".md")
	if err := writeFileString(promptFile, body, 0o644); err != nil {
		return err
	}

	// status=running + last_dispatch (idle fallback の grace 用)
	_ = writeFileString(filepath.Join(c.workersDir(), workerID+".status"), "running", 0o644)
	_ = writeFileString(filepath.Join(c.workersDir(), workerID+".last_dispatch"), nowUnixString(), 0o644)

	// 各 dispatch で fresh context にするため launch script で pane を respawn。
	launch := filepath.Join(c.StateDir, "bin", "launch-"+workerID+".sh")
	if fi, err := os.Stat(launch); err == nil && fi.Mode()&0o100 != 0 {
		_ = respawnPane(paneID, "bash "+launch)
		// TUI ready を待つ (最大 60×3s)
		for i := 0; i < 60; i++ {
			time.Sleep(3 * time.Second)
			content, _ := tmuxOutput("capture-pane", "-t", paneID, "-p", "-S", "-20")
			if strings.Contains(content, "❯") || strings.Contains(content, "╭") ||
				strings.Contains(content, "bypass permissions") || strings.Contains(content, "Claude Code") {
				break
			}
		}
	}

	// prompt をファイル参照で注入 (text と Enter は分けて送る)
	tmuxSendKeys(paneID, fmt.Sprintf("Read %s and follow the instructions.", promptFile))
	time.Sleep(time.Second)
	tmuxSendKeys(paneID, "Enter")

	_ = writeFileString(filepath.Join(c.dispatchDir(), taskID+".last"), nowUnixString(), 0o644)
	c.logf("task=%s worker=%s action=%s status=dispatched", taskID, workerID, action)
	return nil
}

// cmdDispatch は bash cmd_dispatch の移植。flock → maintenance → auto-init →
// task ごとに schedule/status を見て dispatch/restart。
func (c *Crew) cmdDispatch(once bool, targetWorkers ...string) int {
	_ = os.MkdirAll(c.StateDir, 0o755)
	lockFile := filepath.Join(c.StateDir, "dispatch.lock")
	unlock, ok := tryFlock(lockFile)
	if !ok {
		c.logf("dispatch already running, skipping")
		return 0
	}
	defer unlock()

	// pre-dispatch maintenance (M5 で cleanup を実装、ここでは sync/rotate のみ)
	c.syncRemote()
	c.rotateLog()
	c.cleanupOldPrompts()
	c.cleanupOrphanedWorktrees()
	c.cleanupOrphanedBranches()

	// tmux session が無ければ auto-init
	if !hasSession(c.TmuxSession) {
		c.logf("tmux session %s missing - running init to restore workers", c.TmuxSession)
		if code := c.runInit(); code != 0 {
			c.logf("auto-init failed")
			return 1
		}
	}

	dispatched := 0
	for _, t := range c.Config.Tasks {
		if len(targetWorkers) > 0 && !contains(targetWorkers, t.WorkerID) {
			continue
		}
		if !once && !c.shouldDispatch(t.ID, t.Schedule.Minutes) {
			continue
		}
		status := c.workerStatus(t.WorkerID)
		workerFile := filepath.Join(c.workersDir(), t.WorkerID+".json")
		switch status {
		case "idle":
			paneID := readWorkerPaneID(workerFile)
			if err := c.dispatchTask(paneID, t.ID, t.Prompt, t.WorkerID, t.Action); err == nil {
				dispatched++
			}
		case "running", "rate_limited":
			c.logf("task=%s worker=%s status=skipped (%s)", t.ID, t.WorkerID, status)
		case "dead":
			c.logf("task=%s worker=%s status=dead, attempting restart", t.ID, t.WorkerID)
			if fileExists(workerFile) && c.shouldRestart(workerFile) {
				_ = c.recordRestart(workerFile)
				_ = c.startWorker(t.WorkerID, "")
				c.logf("worker=%s restarted", t.WorkerID)
			} else {
				c.logf("worker=%s restart limit exceeded, skipping", t.WorkerID)
			}
		default:
			c.logf("task=%s worker=%s status=%s (unknown, skipping)", t.ID, t.WorkerID, status)
		}
	}
	c.logf("dispatch completed: %d task(s) dispatched", dispatched)
	return 0
}
