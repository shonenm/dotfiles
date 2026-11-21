# ポップ音で Aqua Voice の hands-free 開始と送信を交互に行う。
# Aqua 側で Activate Hands-Free = F12、Send = F10 を登録しておく。
from talon import actions, noise

# ponytail: Aqua の録音状態を外部から取得できないため交互に押す。Esc や「送信して」で終えるとずれ、空打ち 1 回で戻る
recording = False


def on_pop(active):
    global recording
    actions.key("f10" if recording else "f12")
    recording = not recording


noise.register("pop", on_pop)
