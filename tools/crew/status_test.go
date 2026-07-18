package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestResolvePaneStatus(t *testing.T) {
	cases := []struct {
		name      string
		current   string
		tail      string
		want      string
		persist   bool
		sendEnter bool
	}{
		{"rate limit dialog", "running", "...\nyou hit your limit\n...", "rate_limited", true, true},
		{"still working (esc to interrupt present)", "running", "thinking... esc to interrupt", "running", false, false},
		{"idle (no esc marker)", "running", "❯ ready", "idle", true, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			st, persist, sendEnter := resolvePaneStatus(c.current, c.tail)
			if st != c.want || persist != c.persist || sendEnter != c.sendEnter {
				t.Errorf("got (%q,%v,%v), want (%q,%v,%v)", st, persist, sendEnter, c.want, c.persist, c.sendEnter)
			}
		})
	}
}

func TestDerivedPaths(t *testing.T) {
	dir := t.TempDir()
	claude := filepath.Join(dir, "myproj", ".claude")
	if err := os.MkdirAll(claude, 0o755); err != nil {
		t.Fatal(err)
	}
	cfgPath := filepath.Join(claude, "crew.json")
	os.WriteFile(cfgPath, []byte(`{"workers":[],"tasks":[]}`), 0o644)

	crew, err := LoadCrew(cfgPath)
	if err != nil {
		t.Fatal(err)
	}
	if crew.ProjectName != "myproj" {
		t.Errorf("ProjectName=%q", crew.ProjectName)
	}
	if crew.TmuxSession != "crew-myproj" {
		t.Errorf("TmuxSession=%q (want crew-myproj)", crew.TmuxSession)
	}
	if filepath.Base(crew.StateDir) != "myproj" {
		t.Errorf("StateDir=%q", crew.StateDir)
	}
}

func TestConfigOverridesSessionAndState(t *testing.T) {
	dir := t.TempDir()
	claude := filepath.Join(dir, "p", ".claude")
	os.MkdirAll(claude, 0o755)
	cfgPath := filepath.Join(claude, "crew.json")
	os.WriteFile(cfgPath, []byte(`{"workers":[],"tasks":[],"tmux_session":"custom","state_dir":"/tmp/custom-state"}`), 0o644)

	crew, _ := LoadCrew(cfgPath)
	if crew.TmuxSession != "custom" {
		t.Errorf("TmuxSession override: %q", crew.TmuxSession)
	}
	if crew.StateDir != "/tmp/custom-state" {
		t.Errorf("StateDir override: %q", crew.StateDir)
	}
}

func TestCmdStatusTableNoState(t *testing.T) {
	// worker はいるが state file 無し → status "unknown", "(no dispatch)"
	dir := t.TempDir()
	claude := filepath.Join(dir, "p", ".claude")
	os.MkdirAll(claude, 0o755)
	cfgPath := filepath.Join(claude, "crew.json")
	os.WriteFile(cfgPath, []byte(`{"workers":[{"id":"w1","model":"sonnet"}],"tasks":[]}`), 0o644)

	crew, _ := LoadCrew(cfgPath)
	// state dir が無い状態で workerStatus は "unknown" を返すべき
	if got := crew.workerStatus("w1"); got != "unknown" {
		t.Errorf("workerStatus with no state: got %q want unknown", got)
	}
	if got := crew.latestDispatch("w1"); got != "" {
		t.Errorf("latestDispatch with no dispatch: got %q", got)
	}
}
