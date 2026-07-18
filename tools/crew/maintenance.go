package main

// dispatch 前の maintenance。M5 で実装する。M4 では cmdDispatch を通すための no-op stub。
// (syncRemote / detectDefaultBranch は gitx.go で実装済み)

func (c *Crew) rotateLog()                {} // TODO(M5): _rotate_log
func (c *Crew) cleanupOldPrompts()        {} // TODO(M5): _cleanup_old_prompts
func (c *Crew) cleanupOrphanedWorktrees() {} // TODO(M5): _cleanup_orphaned_worktrees
func (c *Crew) cleanupOrphanedBranches()  {} // TODO(M5): _cleanup_orphaned_branches
