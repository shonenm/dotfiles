# ポップ音で Aqua Voice の hands-free 開始と送信を交互に行う。
# Aqua 側で Activate Hands-Free = F12、Send = F10 を登録しておく。
import time

from talon import Context, Module, actions, noise

mod = Module()
# rex.talon などの音声コマンドを録音中に反応させないための tag。
mod.tag("aqua_recording", desc="Aqua Voice が録音中")
ctx = Context()

# Talon の pop 検出には感度設定がないため、開始だけ短い間隔の連続ポップを要求して物音での誤起動を防ぐ。
POP_WINDOW = 0.5

# ponytail: Aqua の録音状態を外部から取得できないため交互に押す。Esc や「送信して」で終えるとずれ、空打ち 1 回で戻る
recording = False
# talon pops で変える。Talon の再起動や aqua_pop.py の reload で 2 に戻る。
start_pops = 2
pops = 0
last_pop = 0.0


@mod.action_class
class Actions:
    def aqua_pop_count(count: int = 0) -> int:
        """Aqua Voice の録音開始に要るポップ音の回数を変え、現在の回数を返す。0 なら変えない"""
        global start_pops
        if count:
            start_pops = count
        return start_pops


def on_pop(active):
    global recording, pops, last_pop
    if not recording:
        # talon off の間はポップ音で録音を始めない。録音中なら送信はする。
        if not actions.speech.enabled():
            return
        now = time.monotonic()
        pops = pops + 1 if now - last_pop <= POP_WINDOW else 1
        last_pop = now
        if pops < start_pops:
            return
        pops = 0
        actions.user.rex_copy_mode_exit()
    actions.key("f10" if recording else "f12")
    recording = not recording
    ctx.tags = ["user.aqua_recording"] if recording else []


noise.register("pop", on_pop)
