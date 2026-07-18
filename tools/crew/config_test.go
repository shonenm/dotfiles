package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

const sample = `{
  "workers": [
    {
      "id": "refactor",
      "model": "sonnet",
      "system_prompt": "do the thing",
      "permissions": {"allow": ["Bash(git:*)", "Read"], "deny": ["Bash(sudo:*)"]}
    }
  ],
  "tasks": [
    {"id": "t1", "pattern": "standing", "worker_id": "refactor", "prompt": "p1",
     "schedule": {"type": "interval", "minutes": 5}},
    {"id": "t2", "pattern": "standing", "worker_id": "refactor", "action": "issue-only", "prompt": "p2",
     "schedule": {"type": "interval", "minutes": 1}}
  ],
  "layout": {"panes_per_window": 2}
}`

func writeTemp(t *testing.T, content string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "crew.json")
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestLoadConfig(t *testing.T) {
	c, err := LoadConfig(writeTemp(t, sample))
	if err != nil {
		t.Fatal(err)
	}
	if len(c.Workers) != 1 || c.Workers[0].ID != "refactor" || c.Workers[0].Model != "sonnet" {
		t.Fatalf("worker parse: %+v", c.Workers)
	}
	if len(c.Tasks) != 2 {
		t.Fatalf("want 2 tasks, got %d", len(c.Tasks))
	}
	// action デフォルト "fix"
	if c.Tasks[0].Action != "fix" {
		t.Errorf("task0 action default: want fix, got %q", c.Tasks[0].Action)
	}
	if c.Tasks[1].Action != "issue-only" {
		t.Errorf("task1 action: want issue-only, got %q", c.Tasks[1].Action)
	}
	if c.Tasks[0].Schedule.Minutes != 5 {
		t.Errorf("schedule minutes: %d", c.Tasks[0].Schedule.Minutes)
	}
	if c.Layout.PanesPerWindow != 2 {
		t.Errorf("panes_per_window: %d", c.Layout.PanesPerWindow)
	}
}

func TestPermissionsPreservedAsRawMessage(t *testing.T) {
	c, err := LoadConfig(writeTemp(t, sample))
	if err != nil {
		t.Fatal(err)
	}
	// permissions は型付けせず、未知フィールドも含めて往復できる
	var perms map[string]any
	if err := json.Unmarshal(c.Workers[0].Permissions, &perms); err != nil {
		t.Fatal(err)
	}
	allow, ok := perms["allow"].([]any)
	if !ok || len(allow) != 2 {
		t.Fatalf("permissions.allow round-trip: %+v", perms)
	}
}

func TestDefaultPanesPerWindow(t *testing.T) {
	c, err := LoadConfig(writeTemp(t, `{"workers":[],"tasks":[]}`))
	if err != nil {
		t.Fatal(err)
	}
	if c.Layout.PanesPerWindow != 1 {
		t.Errorf("default panes_per_window: want 1, got %d", c.Layout.PanesPerWindow)
	}
}

func TestWorkerLookup(t *testing.T) {
	c, _ := LoadConfig(writeTemp(t, sample))
	if w, ok := c.Worker("refactor"); !ok || w.Model != "sonnet" {
		t.Errorf("Worker lookup failed")
	}
	if _, ok := c.Worker("nope"); ok {
		t.Errorf("Worker(nope) should not exist")
	}
}
