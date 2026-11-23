# Rex の pane と tab を音声で操作する。Aqua Voice の録音中は rex.talon が無効になる。
from collections import Counter
import difflib
import json
from pathlib import Path
import re
import shutil
import subprocess
import threading

from talon import Context, Module, actions, app, canvas, cron, ui

BUNDLE = "com.superlogical.rex"
# Talon は login shell の PATH を持たないため、Rex.app 同梱の CLI を直接使う。
# tab 一覧と移動の action は common/rex の voice.lua にある。
VOICE_LUA = str(Path.home() / ".config/rex/voice.lua")
REX = shutil.which("rex") or str(Path.home() / "Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex")

mod = Module()
mod.tag("rex_commands", desc="rex.talon の zoom を有効にする")
mod.tag("rex_tabs", desc="rex.talon の tab 名での移動を有効にする")
# 同じ tab 名を続けて言われたら、その中の agent pane を順に移る。
last_target = None
# talon-speech で段階的に切り替える。Talon の再起動や rex.py の reload で pop に戻る。
level_ctx = Context()
LEVELS = {"pop": [], "rex": ["user.rex_commands"], "tabs": ["user.rex_commands", "user.rex_tabs"]}


def rex(*args):
    result = subprocess.run([REX, "--autostart=false", *args], capture_output=True, text=True, timeout=20)
    if result.returncode:
        print(f"rex {' '.join(args)}: {result.stderr.strip()}")
    return result


def background(*commands):
    # remote host への接続は 1 秒以上かかるため、Talon の main thread で待たない。順序は保つ。
    threading.Thread(target=lambda: [rex(*command) for command in commands], daemon=True).start()


DIGITS = "zero one two three four five six seven eight nine".split()


def spoken(text):
    # Conformer は数字を単語で返すため、slot-1 は slot one と呼ぶ。
    text = re.sub(r"[0-9]", lambda m: " " + DIGITS[int(m.group())] + " ", text.lower())
    return re.sub(r"[^a-z]+", " ", text).strip()


def refresh():
    def collect():
        result = rex("do", "--json", VOICE_LUA, "--action", "dotfiles_voice_tabs")
        if result.returncode:
            return
        tabs = json.loads(result.stdout)
        counts = Counter(spoken(t["label"]) for t in tabs)
        names = {}
        for t in tabs:
            # 複数の session にある tab 名は session 名を付けて呼ぶ。
            name = spoken(t["label"]) if counts[spoken(t["label"])] == 1 else spoken(t["session"] + " " + t["label"])
            names[name] = json.dumps([t.get("host"), t["session_id"], t["window_id"], name])
        global tabs_by_name
        tabs_by_name = names
    threading.Thread(target=collect, daemon=True).start()


tabs_by_name = {}
subtitle = None


def show(text):
    # Talon 標準の字幕は大きく画面下に出るため止め、実行したコマンドだけを画面中央に小さく出す。
    global subtitle
    if subtitle:
        subtitle.close()
    screen = ui.main_screen().rect
    subtitle = canvas.Canvas.from_rect(ui.Rect(screen.x, screen.y + screen.height / 2 - 20, screen.width, 40))

    def draw(c):
        c.paint.textsize = 18
        c.paint.color = "ffffffcc"
        width = c.paint.measure_text(text)[1].width
        c.draw_text(text, c.rect.center.x - width / 2, c.rect.center.y + 6)
    subtitle.register("draw", draw)
    subtitle.freeze()
    closing = subtitle
    cron.after("800ms", closing.close)


@mod.action_class
class Actions:
    def talon_voice_level(level: str = "") -> str:
        """音声操作の段階を off / pop / rex / tabs に切り替え、現在の段階を返す。空なら変えない"""
        if level == "off":
            actions.speech.disable()
        elif level in LEVELS:
            actions.speech.enable()
            level_ctx.tags = LEVELS[level]
        elif level:
            raise ValueError(f"unknown level: {level}")
        if not actions.speech.enabled():
            return "off"
        return next(name for name, tags in LEVELS.items() if set(tags) == set(level_ctx.tags))

    def rex_phrase(phrase: str):
        """発話がコマンド名か tab 名に十分似ているときだけ実行する"""
        names = ["zoom", *(tabs_by_name if "user.rex_tabs" in level_ctx.tags else [])]
        # ponytail: 文字列の類似度だけで判定する。誤爆や取りこぼしが多ければ cutoff を調整するか、呼び名を足す
        match = difflib.get_close_matches(phrase.lower().strip(), names, n=1, cutoff=0.7)
        print(f"rex phrase: {phrase!r} -> {match}")
        text = match[0] if match else ""
        if text == "zoom":
            show("zoom")
            background(("do", "pane.zoom"))
        elif text:
            actions.user.rex_tab(tabs_by_name[text])

    def rex_copy_mode_exit():
        """Rex が前面なら copy mode を抜け、音声入力の文字が copy mode の key にならないようにする"""
        if ui.active_app().bundle == BUNDLE:
            background(("do", "pane.copy_mode.exit"))

    def rex_tab(target: str):
        """Rex の tab を開き、最初の agent pane へ focus する。同じ tab が続けば次の agent pane へ"""
        global last_target
        host, session, window, name = json.loads(target)
        show(name)
        args = ("session=" + session, "window=" + window, *(["next=1"] if target == last_target else []))
        last_target = target

        def go():
            if not host:
                rex("do", "dotfiles_voice_go", *args)
            # remote の tab は voice.lua の key binding で動かす。key から起動すると Rex app の host 接続を使える。
            elif rex("do", "dotfiles_voice_target", "host=" + host, *args).returncode == 0:
                cron.after("0s", lambda: actions.key("cmd-ctrl-alt-shift-v"))
        threading.Thread(target=go, daemon=True).start()


app.register("ready", refresh)
# tab の増減は Rex に戻ったときに拾う。
ui.register("app_activate", lambda application: application.bundle == BUNDLE and refresh())
