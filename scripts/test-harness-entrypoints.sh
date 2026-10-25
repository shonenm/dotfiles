#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
help=$("$root/scripts/dots" help)
for command in apply update check doctor lock; do
  grep -q "  $command" <<< "$help"
done
if "$root/scripts/dots" unknown >/dev/null 2>&1; then
  echo "dots accepted an unknown command" >&2
  exit 1
fi

python3 - "$root" <<'PY'
import os, pathlib, shutil, subprocess, sys, tempfile, tomllib
root = pathlib.Path(sys.argv[1])
dots = (root / "scripts/dots").read_text()
update_case = dots.split("  update)\n", 1)[1].split("    ;;\n", 1)[0]
assert "git -C \"$root\" pull --ff-only" in update_case
assert "update-mise-lock" in update_case
assert "commit_mise_lock" in update_case
assert "commit --only" in dots
assert "git push" not in dots
lock_script = (root / "scripts/update-mise-lock").read_text()
assert 'XDG_CACHE_HOME="$tmp/cache"' in lock_script
assert 'MISE_LOG_LEVEL="${MISE_LOG_LEVEL:-warn}"' in lock_script
assert "Processing .*tool" in lock_script
assert "python3 -c" in lock_script
assert not any(
    line.lstrip().startswith("mise lock") and ("--quiet" in line or " -q " in line)
    for line in lock_script.splitlines()
)
config = tomllib.loads((root / "common/mise/.config/mise/config.toml").read_text())
linux = tomllib.loads((root / "config/mise-linux.toml").read_text())
lock = tomllib.loads((root / "common/mise/.config/mise/mise.lock").read_text())
assert config["settings"]["lockfile"] is True
assert config["settings"]["minimum_release_age"] == "3d"
assert len(lock["tools"]) == len(config["tools"]) + len(linux["tools"])
for tools, required in (
    (config["tools"], {"linux-x64", "linux-arm64", "macos-x64", "macos-arm64"}),
    (linux["tools"], {"linux-x64", "linux-arm64"}),
):
    for name in tools:
        entries = lock["tools"].get(name.split("[", 1)[0], [])
        assert entries, name
        platforms = {key.removeprefix("platforms.") for entry in entries for key in entry if key.startswith("platforms.")}
        backends = {entry.get("backend", "") for entry in entries}
        if not platforms and all(backend.startswith(("cargo:", "npm:")) for backend in backends):
            continue
        assert required <= platforms, (name, required - platforms)
for line in (root / "config/packages.npm.txt").read_text().splitlines():
    line = line.strip()
    if line and not line.startswith("#"):
        assert line.count("@") >= (2 if line.startswith("@") else 1), line
install = (root / "install.sh").read_text()
assert "materialize_mise_lock" in install
assert r"mise\.lock" in (root / "common/mise/.stow-local-ignore").read_text()

# Keep TMPDIR below a caller project, like ~/.cache/tmp below a home mise.toml.
with tempfile.TemporaryDirectory() as directory:
    sandbox = pathlib.Path(directory)
    fixture = sandbox / "repo"
    for relative in ("scripts/update-mise-lock", "common/mise/.config/mise/config.toml", "config/mise-linux.toml"):
        target = fixture / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / relative, target)
    caller = sandbox / "project"
    caller.mkdir()
    (caller / "mise.toml").write_text('[tools]\n"github:Gaurav-Gosain/tuios" = "0.10.0"\n')
    temp_root = caller / ".cache/tmp"
    temp_root.mkdir(parents=True)
    bin_dir = sandbox / "bin"
    bin_dir.mkdir()
    fake_mise = bin_dir / "mise"
    source_lock = root / "common/mise/.config/mise/mise.lock"
    fake_mise.write_text(f'''#!/usr/bin/env python3
import os, pathlib, re, sys
config_home = pathlib.Path(os.environ["XDG_CONFIG_HOME"])
assert pathlib.Path.cwd() == config_home, "caller project config leaks into global lock"
assert config_home == config_home.resolve(), "temp config path is not canonical"
assert config_home.parent == pathlib.Path(os.environ["TMPDIR"]).resolve()
assert os.environ.get("MISE_CEILING_PATHS") == str(config_home), "parent project config leaks into global lock"
assert os.environ.get("MISE_TRUSTED_CONFIG_PATHS") == str(config_home / "mise"), "only copied configs should be trusted"
assert sys.argv[1:3] == ["lock", "-g"]
text = pathlib.Path({str(source_lock)!r}).read_text()
if os.environ.get("TEST_OMIT_TUIOS"):
    text = re.sub(r'\\n\\[\\[tools\\."github:Gaurav-Gosain/tuios"\\]\\].*?(?=\\n\\[\\[tools\\.|\\Z)', '\\n', text, flags=re.S)
(config_home / "mise/mise.lock").write_text(text)
''')
    fake_mise.chmod(0o755)
    fake_gh = bin_dir / "gh"
    fake_gh.write_text("#!/bin/sh\nexit 1\n")
    fake_gh.chmod(0o755)
    # macOS mktemp without a template ignores TMPDIR; force the Linux placement here.
    fake_mktemp = bin_dir / "mktemp"
    fake_mktemp.write_text(f'#!/bin/sh\nexec "{shutil.which("mktemp")}" -d "$TMPDIR/lock.XXXXXX"\n')
    fake_mktemp.chmod(0o755)
    env = dict(os.environ, PATH=f"{bin_dir}{os.pathsep}{os.environ['PATH']}", TMPDIR=str(temp_root))
    command = ["bash", str(fixture / "scripts/update-mise-lock")]
    result = subprocess.run(command, cwd=caller, env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    destination = fixture / "common/mise/.config/mise/mise.lock"
    verified = destination.read_bytes()
    assert "github:Gaurav-Gosain/tuios" in tomllib.loads(verified.decode())["tools"]
    result = subprocess.run(command, cwd=caller, env=dict(env, TEST_OMIT_TUIOS="1"), capture_output=True, text=True)
    assert result.returncode != 0
    assert "mise lockfile is missing github:Gaurav-Gosain/tuios" in result.stderr, result.stderr
    assert destination.read_bytes() == verified, "invalid generation replaced the existing lockfile"
PY

echo "harness entrypoint tests: OK"
