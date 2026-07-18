package main

import (
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// 色付き status ログ (bash _info/_error/_success、stderr)。
func infof(format string, a ...any)    { fmt.Fprintf(os.Stderr, "\033[0;36minfo\033[0m "+format+"\n", a...) }
func errorf(format string, a ...any)   { fmt.Fprintf(os.Stderr, "\033[0;31merror\033[0m "+format+"\n", a...) }
func successf(format string, a ...any) { fmt.Fprintf(os.Stderr, "\033[0;32mok\033[0m "+format+"\n", a...) }

// logf は bash _log の移植: "[ts] msg" を LOG_FILE に追記しつつ stderr にも出す。
func (c *Crew) logf(format string, a ...any) {
	msg := fmt.Sprintf(format, a...)
	line := fmt.Sprintf("[%s] %s\n", time.Now().Format("2006-01-02 15:04:05"), msg)
	if err := os.MkdirAll(filepath.Dir(c.LogFile), 0o755); err == nil {
		if f, err := os.OpenFile(c.LogFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644); err == nil {
			_, _ = f.WriteString(line)
			_ = f.Close()
		}
	}
	fmt.Fprint(os.Stderr, line)
}
