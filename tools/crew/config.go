package main

import (
	"encoding/json"
	"fmt"
	"os"
)

// Config は crew.json の内容。permissions / mcp_config は Claude 所有の進化する
// スキーマなので json.RawMessage で保持し、型付けせず往復させる（ralph-lib の教訓）。
type Config struct {
	Workers     []Worker `json:"workers"`
	Tasks       []Task   `json:"tasks"`
	Layout      Layout   `json:"layout"`
	TmuxSession  string `json:"tmux_session"`  // 省略時 crew-<project>
	StateDir     string `json:"state_dir"`     // 省略時 <runtime>/ralph-crew/<project>
	WorktreePath string `json:"worktree_path"` // worker 個別指定が無い場合の fallback
}

type Worker struct {
	ID           string          `json:"id"`
	Model        string          `json:"model"`
	SystemPrompt string          `json:"system_prompt"`
	MCPConfig    string          `json:"mcp_config,omitempty"`
	WorktreePath string          `json:"worktree_path,omitempty"`
	Permissions  json.RawMessage `json:"permissions,omitempty"`
}

type Task struct {
	ID       string   `json:"id"`
	Pattern  string   `json:"pattern"`
	WorkerID string   `json:"worker_id"`
	Action   string   `json:"action"`
	Prompt   string   `json:"prompt"`
	Schedule Schedule `json:"schedule"`
}

type Schedule struct {
	Type    string `json:"type"`
	Minutes int    `json:"minutes"`
}

type Layout struct {
	PanesPerWindow int `json:"panes_per_window"`
}

// LoadConfig は crew.json を読んでデフォルトを補完する。
// bash 版のデフォルト: action="fix", layout.panes_per_window=1。
func LoadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", path, err)
	}
	var c Config
	if err := json.Unmarshal(data, &c); err != nil {
		return nil, fmt.Errorf("parsing %s: %w", path, err)
	}
	c.applyDefaults()
	return &c, nil
}

func (c *Config) applyDefaults() {
	if c.Layout.PanesPerWindow < 1 {
		c.Layout.PanesPerWindow = 1
	}
	for i := range c.Tasks {
		if c.Tasks[i].Action == "" {
			c.Tasks[i].Action = "fix"
		}
	}
}

// worker は id で引く。
func (c *Config) Worker(id string) (*Worker, bool) {
	for i := range c.Workers {
		if c.Workers[i].ID == id {
			return &c.Workers[i], true
		}
	}
	return nil, false
}
