package main

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// shouldDispatch は bash _should_dispatch: dispatch/<task>.last からの経過分が
// interval_minutes 以上か。未 dispatch (ファイル無し) なら常に true。
func (c *Crew) shouldDispatch(taskID string, intervalMinutes int) bool {
	lastFile := filepath.Join(c.dispatchDir(), taskID+".last")
	data, err := os.ReadFile(lastFile)
	if err != nil {
		return true // never dispatched
	}
	last, err := strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64)
	if err != nil {
		return true
	}
	elapsedMin := (time.Now().Unix() - last) / 60
	return elapsedMin >= int64(intervalMinutes)
}

const (
	restartWindow      = 300 // 5 分
	restartMaxInWindow = 3
)

// shouldRestart は bash _should_restart: 直近 restartWindow 秒の restart_timestamps が
// restartMaxInWindow 未満か。
func (c *Crew) shouldRestart(workerFile string) bool {
	ws := readWorkerRestartState(workerFile)
	now := time.Now().Unix()
	recent := 0
	for _, ts := range ws.RestartTimestamps {
		if ts > now-restartWindow {
			recent++
		}
	}
	return recent < restartMaxInWindow
}

// recordRestart は restart_timestamps に now を追記 (atomic write)。
// worker.json は crew 所有スキーマなので WorkerMeta で往復し固定順を保つ。
func (c *Crew) recordRestart(workerFile string) error {
	raw, err := os.ReadFile(workerFile)
	if err != nil {
		return err
	}
	var meta WorkerMeta
	if err := jsonUnmarshal(raw, &meta); err != nil {
		return err
	}
	meta.RestartTimestamps = append(meta.RestartTimestamps, nowUnix())
	return writeJSONAtomic(workerFile, meta)
}
