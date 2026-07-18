package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// _cleanup_old_prompts: prompts の 24h 超ファイルを削除。
func (c *Crew) cleanupOldPrompts() {
	dir := filepath.Join(c.StateDir, "prompts")
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	cutoff := time.Now().Add(-1440 * time.Minute)
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		info, err := e.Info()
		if err == nil && info.ModTime().Before(cutoff) {
			_ = os.Remove(filepath.Join(dir, e.Name()))
		}
	}
}

// _rotate_log: LOG_FILE が 1MB 超なら末尾 1000 行に切り詰め。
func (c *Crew) rotateLog() {
	info, err := os.Stat(c.LogFile)
	if err != nil {
		return
	}
	if info.Size() <= 1048576 {
		return
	}
	data, err := os.ReadFile(c.LogFile)
	if err != nil {
		return
	}
	lines := strings.Split(strings.TrimRight(string(data), "\n"), "\n")
	if len(lines) > 1000 {
		lines = lines[len(lines)-1000:]
	}
	_ = os.WriteFile(c.LogFile, []byte(strings.Join(lines, "\n")+"\n"), 0o644)
	c.logf("log rotated (was %d bytes)", info.Size())
}

// _cleanup_orphaned_worktrees: STATE_DIR/fix/*/ を git worktree remove or rm -rf。
func (c *Crew) cleanupOrphanedWorktrees() {
	fixDir := filepath.Join(c.StateDir, "fix")
	entries, err := os.ReadDir(fixDir)
	if err != nil {
		return
	}
	registered, _ := exec.Command("git", "-C", c.ProjectDir, "worktree", "list", "--porcelain").Output()
	cleaned := 0
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		wtDir := filepath.Join(fixDir, e.Name())
		if !strings.Contains(string(registered), wtDir) {
			_ = os.RemoveAll(wtDir)
			cleaned++
			continue
		}
		if exec.Command("git", "-C", c.ProjectDir, "worktree", "remove", wtDir).Run() == nil {
			cleaned++
		}
	}
	if cleaned > 0 {
		_ = exec.Command("git", "-C", c.ProjectDir, "worktree", "prune").Run()
		c.logf("cleanup: removed %d orphaned worktree(s)", cleaned)
	}
}

// _cleanup_orphaned_branches: worktree に紐づかない crew/* branch を削除。
func (c *Crew) cleanupOrphanedBranches() {
	wtBranches := map[string]bool{}
	for _, w := range gitWorktreeBranches(c.ProjectDir) {
		wtBranches[w] = true
	}
	out, err := exec.Command("git", "-C", c.ProjectDir, "branch", "--list", "crew/*").Output()
	if err != nil {
		return
	}
	cleaned := 0
	for _, line := range strings.Split(string(out), "\n") {
		branch := strings.TrimSpace(strings.TrimLeft(line, "* "))
		if branch == "" || wtBranches[branch] {
			continue
		}
		if exec.Command("git", "-C", c.ProjectDir, "branch", "-D", branch).Run() == nil {
			cleaned++
		}
	}
	if cleaned > 0 {
		c.logf("cleanup: removed %d orphaned crew/* branch(es)", cleaned)
	}
}

// gitWorktreeBranches は porcelain の branch 行から branch 名一覧。
func gitWorktreeBranches(projectDir string) []string {
	out, err := exec.Command("git", "-C", projectDir, "worktree", "list", "--porcelain").Output()
	if err != nil {
		return nil
	}
	var branches []string
	for _, line := range strings.Split(string(out), "\n") {
		if b, ok := strings.CutPrefix(line, "branch refs/heads/"); ok {
			branches = append(branches, b)
		}
	}
	return branches
}
