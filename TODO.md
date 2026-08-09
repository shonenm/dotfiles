# Harness consistency plan

- Add one `dots` entry point for apply, update, check, doctor, and dependency lock refresh.
- Add a tracked native mise lockfile for supported macOS/Linux architectures and use it during installs.
- Pin global npm CLI versions and make installer reconciliation version-aware.
- Add scheduled Renovate and mise-lock pull requests with a three-day release delay.
- Make CI call the same repository check command used locally.
- Update installation documentation and validate all affected paths.
