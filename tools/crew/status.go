package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

const graceSeconds = 15 // dispatch 直後の TUI レンダ待ち猶予

// workerState は worker.json の必要フィールドのみ (pane_id)。
type workerState struct {
	PaneID string `json:"pane_id"`
}

// resolvePaneStatus は running/pane あり時の grace 後判定を純粋関数化したもの。
// 戻り: 新 status, status file に書くか, Enter を送るか (rate limit 自動確認)。
func resolvePaneStatus(current, paneTail string) (status string, persist, sendEnter bool) {
	if strings.Contains(paneTail, "hit your limit") {
		return "rate_limited", true, true
	}
	if !strings.Contains(paneTail, "esc to interrupt") {
		return "idle", true, false
	}
	return current, false, false
}

// workerStatus は bash _crew_worker_status の移植。副作用 (rate limit の Enter 送信、
// status file 更新) も含めて忠実に再現する。
func (c *Crew) workerStatus(workerID string) string {
	statusFile := filepath.Join(c.workersDir(), workerID+".status")
	workerFile := filepath.Join(c.workersDir(), workerID+".json")

	paneID := ""
	if data, err := os.ReadFile(workerFile); err == nil {
		var ws workerState
		if json.Unmarshal(data, &ws) == nil {
			paneID = ws.PaneID
		}
		if paneID != "" && !paneExists(paneID) {
			return "dead"
		}
	}

	status := "unknown"
	if data, err := os.ReadFile(statusFile); err == nil {
		status = strings.TrimSpace(string(data))
	}

	// running かつ pane あり: dispatch から grace 秒経過後に TUI footer を見て idle 判定。
	if status == "running" && paneID != "" {
		elapsed := int64(999)
		lastFile := filepath.Join(c.workersDir(), workerID+".last_dispatch")
		if data, err := os.ReadFile(lastFile); err == nil {
			if last, err := strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64); err == nil {
				elapsed = time.Now().Unix() - last
			}
		}
		if elapsed >= graceSeconds {
			newStatus, persist, sendEnter := resolvePaneStatus(status, capturePaneTail(paneID, 8))
			if sendEnter {
				tmuxSendKeys(paneID, "Enter")
			}
			if persist {
				status = newStatus
				_ = os.WriteFile(statusFile, []byte(status), 0o644)
			}
		}
	}
	return status
}

// cmdStatus は bash cmd_status の移植 (table / --json)。
func (c *Crew) cmdStatus(jsonMode bool) error {
	if jsonMode {
		result := map[string]string{}
		entries, _ := filepath.Glob(filepath.Join(c.workersDir(), "*.status"))
		for _, f := range entries {
			wid := strings.TrimSuffix(filepath.Base(f), ".status")
			result[wid] = c.workerStatus(wid)
		}
		// bash は登場順だが JSON object なので順序非依存。ソートして安定出力にする。
		out := encodeStableObject(result)
		fmt.Println(out)
		return nil
	}

	for _, w := range c.Config.Workers {
		st := c.workerStatus(w.ID)
		last := c.latestDispatch(w.ID)
		if last == "" {
			last = "(no dispatch)"
		}
		fmt.Printf("  %-20s %-10s %s\n", w.ID, st, last)
	}
	return nil
}

// latestDispatch は worker の最新 dispatch を "taskID@HH:MM:SS" で返す。
func (c *Crew) latestDispatch(workerID string) string {
	entries, _ := filepath.Glob(filepath.Join(c.dispatchDir(), "*.last"))
	result := ""
	for _, f := range entries {
		tid := strings.TrimSuffix(filepath.Base(f), ".last")
		// この task の worker が一致するか
		match := false
		for _, t := range c.Config.Tasks {
			if t.ID == tid && t.WorkerID == workerID {
				match = true
				break
			}
		}
		if !match {
			continue
		}
		data, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		epoch, err := strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64)
		if err != nil {
			continue
		}
		result = fmt.Sprintf("%s@%s", tid, time.Unix(epoch, 0).Format("15:04:05"))
	}
	return result
}

// encodeStableObject は {"k":"v",...} をキーソートで出力 (bash の文字列連結 JSON 互換)。
func encodeStableObject(m map[string]string) string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys))
	for _, k := range keys {
		parts = append(parts, fmt.Sprintf("%q:%q", k, m[k]))
	}
	return "{" + strings.Join(parts, ",") + "}"
}
