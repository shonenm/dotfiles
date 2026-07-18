package main

import (
	"os"
	"path/filepath"
	"strconv"
	"testing"
)

func newTestCrew(t *testing.T) *Crew {
	t.Helper()
	dir := t.TempDir()
	claude := filepath.Join(dir, "p", ".claude")
	os.MkdirAll(claude, 0o755)
	cfg := filepath.Join(claude, "crew.json")
	os.WriteFile(cfg, []byte(`{"workers":[],"tasks":[]}`), 0o644)
	crew, err := LoadCrew(cfg)
	if err != nil {
		t.Fatal(err)
	}
	// state を temp に固定
	crew.StateDir = filepath.Join(dir, "state")
	crew.LogFile = filepath.Join(crew.StateDir, "logs", "dispatch.log")
	os.MkdirAll(crew.StateDir, 0o755)
	return crew
}

func TestAcquireSingleton(t *testing.T) {
	crew := newTestCrew(t)
	pidfile := filepath.Join(crew.StateDir, "daemon.pid")

	// 初回取得は成功し、自 pid が書かれる
	if err := crew.acquireSingleton(pidfile); err != nil {
		t.Fatalf("first acquire: %v", err)
	}
	data, _ := os.ReadFile(pidfile)
	if got, _ := strconv.Atoi(string(data)); got != os.Getpid() {
		t.Errorf("pidfile pid=%s want %d", data, os.Getpid())
	}

	// 生きた pid が入っている状態での再取得は拒否
	if err := crew.acquireSingleton(pidfile); err == nil {
		t.Error("second acquire should fail (daemon already running)")
	}
}

func TestAcquireSingletonStale(t *testing.T) {
	crew := newTestCrew(t)
	pidfile := filepath.Join(crew.StateDir, "daemon.pid")
	// 絶対に生きていない pid を書く
	os.WriteFile(pidfile, []byte("2147480000"), 0o644)

	if err := crew.acquireSingleton(pidfile); err != nil {
		t.Fatalf("stale pidfile should be reclaimed: %v", err)
	}
	data, _ := os.ReadFile(pidfile)
	if got, _ := strconv.Atoi(string(data)); got != os.Getpid() {
		t.Errorf("stale not replaced: pidfile=%s", data)
	}
}

func TestProcessAlive(t *testing.T) {
	if !processAlive(os.Getpid()) {
		t.Error("own pid should be alive")
	}
	if processAlive(2147480000) {
		t.Error("bogus pid should not be alive")
	}
	if processAlive(0) || processAlive(-1) {
		t.Error("invalid pids should not be alive")
	}
}
