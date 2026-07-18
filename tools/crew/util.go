package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"syscall"
	"time"
)

// flockNB は非ブロッキング排他ロック (flock -n)。
func flockNB(f *os.File) error {
	return syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
}

// nowUnix はテストで差し替え可能な時刻取得。
var nowUnix = func() int64 { return time.Now().Unix() }

// restartState は worker.json の restart_timestamps のみ抽出する view。
type restartState struct {
	RestartTimestamps []int64 `json:"restart_timestamps"`
}

func readWorkerRestartState(path string) restartState {
	var ws restartState
	if data, err := os.ReadFile(path); err == nil {
		_ = json.Unmarshal(data, &ws)
	}
	return ws
}

func jsonUnmarshal(data []byte, v any) error { return json.Unmarshal(data, v) }

// marshalCompact は compact JSON 文字列 (hook_json 等、jq に渡すので整形不要)。
func marshalCompact(v any) (string, error) {
	b, err := json.Marshal(v)
	return string(b), err
}

// writeJSONAtomic は tmp に整形 JSON を書いて rename (bash の tmp+mv 相当)。
func writeJSONAtomic(path string, v any) error {
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	tmp := fmt.Sprintf("%s.tmp.%d", path, os.Getpid())
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// writeFileString は mkdir -p + write (末尾改行なし版)。
func writeFileString(path, content string, perm os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(content), perm)
}

func nowUnixString() string {
	return fmt.Sprintf("%d", nowUnix())
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func contains(s []string, v string) bool {
	for _, x := range s {
		if x == v {
			return true
		}
	}
	return false
}

// readWorkerPaneID は worker.json の pane_id。
func readWorkerPaneID(path string) string {
	var ws workerState // status.go 定義 (pane_id のみ)
	if data, err := os.ReadFile(path); err == nil {
		_ = json.Unmarshal(data, &ws)
	}
	return ws.PaneID
}

// tryFlock は排他 flock を非ブロッキングで取得。取れれば解放 closure を返す。
// bash の exec 9>lock; flock -n 9 に対応。
func tryFlock(path string) (unlock func(), ok bool) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, false
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return nil, false
	}
	if err := flockNB(f); err != nil {
		_ = f.Close()
		return nil, false
	}
	return func() { _ = f.Close() }, true // close で flock 解放
}
