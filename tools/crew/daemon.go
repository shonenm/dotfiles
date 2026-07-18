package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// processAlive は kill(pid, 0) 相当で生存確認 (bash の kill -0)。
func processAlive(pid int) bool {
	if pid <= 0 {
		return false
	}
	return syscall.Kill(pid, 0) == nil
}

// acquireSingleton は pidfile による多重起動防止。既存 daemon が生きていれば error、
// stale なら除去して自分の pid を書く (bash cmd_daemon の pidfile ロジック)。
func (c *Crew) acquireSingleton(pidfile string) error {
	if data, err := os.ReadFile(pidfile); err == nil {
		if pid, err := strconv.Atoi(strings.TrimSpace(string(data))); err == nil && processAlive(pid) {
			return fmt.Errorf("daemon already running (pid=%d, pidfile=%s)", pid, pidfile)
		}
		c.logf("stale pidfile removed (pidfile=%s)", pidfile)
		_ = os.Remove(pidfile)
	}
	return os.WriteFile(pidfile, []byte(strconv.Itoa(os.Getpid())), 0o644)
}

// cmdDaemon は bash cmd_daemon の移植。singleton + 起動時 init + tick loop +
// signal graceful stop。dispatch は子プロセスとして実行し、非ゼロ終了でも loop は継続。
func (c *Crew) cmdDaemon(intervalSeconds int) int {
	if intervalSeconds < 1 {
		fmt.Fprintf(os.Stderr, "error: invalid --interval: %d (must be positive integer seconds)\n", intervalSeconds)
		return 1
	}
	if err := os.MkdirAll(c.StateDir, 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		return 1
	}
	pidfile := filepath.Join(c.StateDir, "daemon.pid")
	if err := c.acquireSingleton(pidfile); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		return 1
	}
	defer os.Remove(pidfile)

	// SIGINT/SIGTERM で ctx をキャンセル → sleep 即中断 → graceful stop。
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// 起動時に必ず init (idempotent)。tmux-continuum の resurrect でも worker を
	// 現セッション状態に一致させる。init 失敗は log のみで継続。
	if code := c.runInit(); code != 0 {
		c.logf("daemon startup: init failed (continuing)")
	}

	self, err := os.Executable()
	if err != nil {
		self = "crew"
	}
	c.logf("daemon starting (pid=%d, interval=%ds, config=%s)", os.Getpid(), intervalSeconds, c.ConfigFile)

	for {
		// dispatch を子プロセスで実行 (flock/fd state を daemon loop に漏らさない)。
		cmd := exec.Command(self, "dispatch", "--config", c.ConfigFile)
		cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
		if err := cmd.Run(); err != nil {
			c.logf("dispatch iteration exited non-zero (continuing): %v", err)
		}
		// interruptible sleep: signal で即座に抜ける (foreground sleep だと停止が遅延)。
		select {
		case <-ctx.Done():
			c.logf("daemon stopping (signal received, pid=%d)", os.Getpid())
			return 0
		case <-time.After(time.Duration(intervalSeconds) * time.Second):
		}
	}
}
