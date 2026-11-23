# Rex の pane と session を音声で操作する。Aqua Voice の録音中は rex.talon が無効になる。
from collections import Counter
import json
from pathlib import Path
import re
import shutil
import subprocess
import threading

from talon import Context, Module, app, cron, ui

BUNDLE = "com.superlogical.rex"
LUA = str(Path(__file__).resolve().with_name("rex_agent.lua"))
# Talon は login shell の PATH を持たないため、Rex.app 同梱の CLI を直接使う。
REX = shutil.which("rex") or str(Path.home() / "Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex")

mod = Module()
mod.list("rex_session", desc="Rex の session。値は [host, session_id] の JSON")
ctx = Context()


def rex(*args):
    result = subprocess.run([REX, "--autostart=false", *args], capture_output=True, text=True, timeout=20)
    if result.returncode:
        print(f"rex {' '.join(args)}: {result.stderr.strip()}")
    return result


def background(*commands):
    # remote host への接続は 1 秒以上かかるため、Talon の main thread で待たない。順序は保つ。
    threading.Thread(target=lambda: [rex(*command) for command in commands], daemon=True).start()


def spoken(text):
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


def refresh():
    def collect():
        result = rex("do", "--json", LUA, "--action", "sessions")
        if result.returncode:
            return
        sessions = json.loads(result.stdout)
        counts = Counter(spoken(s["label"]) for s in sessions)
        names = {}
        for s in sessions:
            value = json.dumps([s.get("host"), s["session_id"]])
            if s.get("host"):
                names[spoken(s["host"] + " " + s["label"])] = value
            # 複数 host にある名前は host 名付きでだけ呼べる。
            if counts[spoken(s["label"])] == 1:
                names[spoken(s["label"])] = value
        cron.after("0s", lambda: ctx.lists.__setitem__("user.rex_session", names))
    threading.Thread(target=collect, daemon=True).start()


@mod.action_class
class Actions:
    def rex_zoom():
        """Rex の focus 中の pane を zoom / 解除する"""
        background(("do", "pane.zoom"))

    def rex_scroll(direction: str):
        """Rex の focus 中の pane を copy mode で半ページ動かす"""
        move = ("do", "pane.copy_mode.move", "to=half_page_" + direction)
        if direction == "up":
            background(("do", "pane.copy_mode.enter"), move)
        else:
            background(move)

    def rex_copy_mode_exit():
        """Rex が前面なら copy mode を抜け、音声入力の文字が copy mode の key にならないようにする"""
        if ui.active_app().bundle == BUNDLE:
            background(("do", "pane.copy_mode.exit"))

    def rex_agent_session(target: str):
        """Rex の session を開き、最初の agent pane へ focus する"""
        host, session = json.loads(target)
        background(("do", LUA, "--action", "agent_session", "session=" + session,
                    *(["host=" + host] if host else [])))


app.register("ready", refresh)
# session の増減は Rex に戻ったときに拾う。
ui.register("app_activate", lambda application: application.bundle == BUNDLE and refresh())
