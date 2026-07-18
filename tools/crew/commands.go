package main

import (
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// cmdSend は bash cmd_send: worker に手動メッセージを注入。
func (c *Crew) cmdSend(workerID, message string) int {
	if workerID == "" {
		errorf("Usage: crew send <worker-id> <message> [--config <path>]")
		return 1
	}
	if message == "" {
		errorf("message is required")
		return 1
	}
	workerFile := filepath.Join(c.workersDir(), workerID+".json")
	if !fileExists(workerFile) {
		errorf("Worker not found: %s", workerID)
		return 1
	}
	paneID := readWorkerPaneID(workerFile)
	if paneID == "" {
		errorf("No pane_id for worker: %s", workerID)
		return 1
	}
	if !paneExists(paneID) {
		errorf("Pane %s no longer exists for %s", paneID, workerID)
		return 1
	}

	msgFile := filepath.Join(c.StateDir, "prompts", fmt.Sprintf("manual-%s-%d.md", workerID, nowUnix()))
	if err := writeFileString(msgFile, message, 0o644); err != nil {
		errorf("%v", err)
		return 1
	}
	_ = writeFileString(filepath.Join(c.workersDir(), workerID+".status"), "running", 0o644)
	tmuxSendKeys(paneID, fmt.Sprintf("Read %s and follow the instructions.", msgFile))
	time.Sleep(time.Second)
	tmuxSendKeys(paneID, "Enter")
	successf("Sent message to %s (%s)", workerID, paneID)
	return 0
}

// cmdRestart は bash cmd_restart: worker を手動再起動。
func (c *Crew) cmdRestart(workerID string) int {
	if workerID == "" {
		errorf("Usage: crew restart <worker-id> [--config <path>]")
		return 1
	}
	windowName := "crew/" + workerID
	if windowExists(c.TmuxSession, windowName) {
		_ = tmuxRun("kill-window", "-t", c.TmuxSession+":"+windowName)
	}
	workerFile := filepath.Join(c.workersDir(), workerID+".json")
	if fileExists(workerFile) {
		_ = c.recordRestart(workerFile)
	}
	if err := c.startWorker(workerID, ""); err != nil {
		return 1
	}
	c.logf("worker=%s manually restarted", workerID)
	return 0
}

// cmdCleanup は bash cmd_cleanup: maintenance をまとめて実行。
func (c *Crew) cmdCleanup() int {
	infof("Cleaning up: %s", c.StateDir)
	c.cleanupOldPrompts()
	c.rotateLog()
	c.cleanupOrphanedWorktrees()
	c.cleanupOrphanedBranches()
	successf("Cleanup completed")
	return 0
}

// cmdTeardown は bash cmd_teardown: session kill + settings 復元 + state 削除。
func (c *Crew) cmdTeardown() int {
	if hasSession(c.TmuxSession) {
		_ = tmuxRun("kill-session", "-t", c.TmuxSession)
		successf("Killed tmux session: %s", c.TmuxSession)
	} else {
		infof("No tmux session: %s", c.TmuxSession)
	}

	// init 時に snapshot した元の settings.local.json を復元 (無ければ worker 用を削除)。
	settingsFile := filepath.Join(c.ProjectDir, ".claude", "settings.local.json")
	backupFile := settingsFile + ".pre-ralph-crew"
	if fileExists(backupFile) {
		_ = os.Rename(backupFile, settingsFile)
		successf("Restored original settings.local.json")
	} else if fileExists(settingsFile) {
		_ = os.Remove(settingsFile)
		successf("Removed worker-scoped settings.local.json")
	}

	// state 削除前に log (logf は mkdir で state を作り直すため順序重要)。
	c.logf("teardown completed")
	_ = os.RemoveAll(c.StateDir)
	successf("Cleaned up state: %s", c.StateDir)
	return 0
}
