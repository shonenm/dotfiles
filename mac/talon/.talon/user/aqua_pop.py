# ポップ音で Aqua Voice の hands-free 開始と送信を交互に行う。
# Aqua 側で Activate Hands-Free = F12、Send = F10 を登録しておく。
from talon import Context, Module, actions, noise

mod = Module()
# rex.talon などの音声コマンドを録音中に反応させないための tag。
mod.tag("aqua_recording", desc="Aqua Voice が録音中")
ctx = Context()

# ponytail: Aqua の録音状態を外部から取得できないため交互に押す。Esc や「送信して」で終えるとずれ、空打ち 1 回で戻る
recording = False


def on_pop(active):
    global recording
    # talon-speech off の間はポップ音で録音を始めない。録音中なら送信はする。
    if not recording and not actions.speech.enabled():
        return
    if not recording:
        actions.user.rex_copy_mode_exit()
    actions.key("f10" if recording else "f12")
    recording = not recording
    ctx.tags = ["user.aqua_recording"] if recording else []


noise.register("pop", on_pop)
