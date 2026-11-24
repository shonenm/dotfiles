# ポップ音で Aqua Voice の hands-free 開始と送信を交互に行う。
# Aqua 側で Activate Hands-Free = F12、Send = F10 を登録しておく。
import time

from talon import Context, Module, actions, noise

mod = Module()
# rex.talon などの音声コマンドを録音中に反応させないための tag。
mod.tag("aqua_recording", desc="Aqua Voice が録音中")
ctx = Context()

# Talon の pop 検出には感度設定がないため、開始だけ短い間隔の 2 連続ポップを要求して物音での誤起動を防ぐ。
DOUBLE_POP_WINDOW = 0.5

# ponytail: Aqua の録音状態を外部から取得できないため交互に押す。Esc や「送信して」で終えるとずれ、空打ち 1 回で戻る
recording = False
last_pop = 0.0


def on_pop(active):
    global recording, last_pop
    if not recording:
        # talon-speech off の間はポップ音で録音を始めない。録音中なら送信はする。
        if not actions.speech.enabled():
            return
        now = time.monotonic()
        if now - last_pop > DOUBLE_POP_WINDOW:
            last_pop = now
            return
        last_pop = 0.0
        actions.user.rex_copy_mode_exit()
    actions.key("f10" if recording else "f12")
    recording = not recording
    ctx.tags = ["user.aqua_recording"] if recording else []


noise.register("pop", on_pop)
