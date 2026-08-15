#!/usr/bin/env python3
"""Small self-check for tmux-layout apply-auto selection."""

import runpy
import tempfile
from pathlib import Path
from types import SimpleNamespace


module = runpy.run_path(str(Path(__file__).with_name("tmux-layout")), run_name="tmux_layout")
with_checksum = module["with_checksum"]
current = with_checksum("80x24,0,0{39x24,0,0,1,40x24,40,0,2}")
vertical = with_checksum("80x24,0,0[80x11,0,0,1,80x12,0,12,2]")

with tempfile.TemporaryDirectory() as tmp:
    layout_dir = Path(tmp)
    (layout_dir / "alpha.layout").write_text(current + "\n")
    (layout_dir / "remembered.layout").write_text(current + "\n")
    (layout_dir / "other.layout").write_text(vertical + "\n")
    module["cmd_apply_auto"].__globals__["LAYOUT_DIR"] = layout_dir
    module["cmd_apply_auto"].__globals__["current_window_id"] = lambda _pane: "@1"

    selected = []
    remembered = "remembered"

    def tmux_get(fmt, _target=None):
        return remembered if fmt == "#{@layout-preset}" else current

    def apply_preset(name, win):
        selected.append((name, win))
        return 0

    module["cmd_apply_auto"].__globals__["tmux_get"] = tmux_get
    module["cmd_apply_auto"].__globals__["apply_preset"] = apply_preset
    args = SimpleNamespace(pane=None)

    assert module["cmd_apply_auto"](args) == 0
    assert selected.pop() == ("remembered", "@1")

    remembered = ""
    assert module["cmd_apply_auto"](args) == 0
    assert selected.pop() == ("alpha", "@1")

    (layout_dir / "alpha.layout").unlink()
    (layout_dir / "remembered.layout").unlink()
    assert module["cmd_apply_auto"](args) == 2

print("tmux-layout: OK")
