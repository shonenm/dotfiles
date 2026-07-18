package main

import (
	"os/exec"
	"strings"
)

// detectDefaultBranch は bash _detect_default_branch: origin/HEAD の指す branch、
// 取れなければ "main"。
func (c *Crew) detectDefaultBranch() string {
	out, err := exec.Command("git", "-C", c.ProjectDir, "symbolic-ref", "refs/remotes/origin/HEAD").Output()
	if err != nil {
		return "main"
	}
	ref := strings.TrimSpace(string(out))
	return strings.TrimPrefix(ref, "refs/remotes/origin/")
}

// syncRemote は bash _sync_remote: origin から fetch --prune。失敗は log のみ。
func (c *Crew) syncRemote() {
	if err := exec.Command("git", "-C", c.ProjectDir, "fetch", "--prune", "origin").Run(); err != nil {
		c.logf("warning: git fetch failed (continuing with current HEAD)")
		return
	}
	c.logf("fetched latest from origin")
}
