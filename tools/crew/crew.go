package main

import (
	"os"
	"path/filepath"
)

// Crew は crew.json + そこから派生する実行時パスを束ねる。
// bash 版 _load_config の PROJECT_DIR / TMUX_SESSION / STATE_DIR / LOG_FILE に対応。
type Crew struct {
	Config      *Config
	ConfigFile  string // 絶対パス
	ProjectDir  string // <config>/.claude/crew.json の 2 つ上
	ProjectName string
	TmuxSession string
	StateDir    string
	LogFile     string
}

// LoadCrew は config を読み、bash 版と同じ規則で派生パスを決める。
func LoadCrew(configPath string) (*Crew, error) {
	cfg, err := LoadConfig(configPath)
	if err != nil {
		return nil, err
	}
	abs, err := filepath.Abs(configPath)
	if err != nil {
		return nil, err
	}
	projectDir := filepath.Dir(filepath.Dir(abs)) // .../project/.claude/crew.json -> .../project
	name := filepath.Base(projectDir)

	tmuxSession := cfg.TmuxSession
	if tmuxSession == "" {
		tmuxSession = "crew-" + name
	}
	stateDir := cfg.StateDir
	if stateDir == "" {
		stateDir = filepath.Join(runtimeBase(), "ralph-crew", name)
	}

	return &Crew{
		Config:      cfg,
		ConfigFile:  abs,
		ProjectDir:  projectDir,
		ProjectName: name,
		TmuxSession: tmuxSession,
		StateDir:    stateDir,
		LogFile:     filepath.Join(stateDir, "logs", "dispatch.log"),
	}, nil
}

// runtimeBase は bash の ${XDG_RUNTIME_DIR:-${TMPDIR:-$HOME/.cache}} と同じ。
func runtimeBase() string {
	if v := os.Getenv("XDG_RUNTIME_DIR"); v != "" {
		return v
	}
	if v := os.Getenv("TMPDIR"); v != "" {
		return v
	}
	return filepath.Join(os.Getenv("HOME"), ".cache")
}

func (c *Crew) workersDir() string  { return filepath.Join(c.StateDir, "workers") }
func (c *Crew) dispatchDir() string { return filepath.Join(c.StateDir, "dispatch") }
