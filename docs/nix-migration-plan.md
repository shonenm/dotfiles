# Nix Migration Plan

dotfiles を GNU Stow + シェルスクリプト構成から Nix (flakes + home-manager + nix-darwin) に段階移行する計画書。

## 0. ゴールと非ゴール

### ゴール
- パッケージ宣言の一元化 (Brewfile / apt / alpine / pixi / npm / cargo / mise → 単一 `flake.nix`)
- `flake.lock` による mac / Linux 横断の再現性
- カスタムスクリプト 60+ 本の宣言的管理 (PATH 流儀は維持)
- macOS システム設定 (aerospace, karabiner, ghostty) の宣言化
- アトミック rollback 能力の獲得

### 非ゴール
- ralph-crew / rcon / Docker worktree フローの変更 (現状維持)
- Claude Code 設定そのものの再設計 (移行は symlink レイヤーのみ)
- NixOS への OS 移行 (Linux 側は既存ディストロ上の Nix のみ)
- 短期的な日常操作速度の改善 (移行直後はむしろ遅くなる)

## 1. 現状インベントリ (調査済み)

| カテゴリ | 規模 | 移行先 |
|---------|-----|--------|
| Brewfile | 92 エントリ (taps 4, formulae ~80, casks ~10) | `home.packages` + `homebrew` (nix-darwin、casks のみ) |
| apt パッケージ | 14 | `home.packages` (Linux 側) |
| alpine パッケージ | 23 | `home.packages` (Linux 側) |
| npm グローバル | 10 (claude-mem, ccusage 等) | npm は `nodejs` + プロジェクト管理 or `writeShellApplication` ラッパー |
| pixi | 38 (sudoless 専用) | nix で代替 (sudoless 専用パスは別途設計) |
| mise tools | 7 (node/python/pnpm/deno/go/cloudflared/cspell) | mise 維持 or Nix へ移行 (要判断) |
| install\_\* シェル関数 | 17 個 (genshijin, claude-mem, rtk, serena, context-mode, dops, quay, lemonade, auto-mode, code-review-graph 等) | overlay + `fetchFromGitHub` / `writeShellApplication` / `claude plugin install` (Claude プラグインは Nix 化対象外) |
| common dotfile dirs | 26 | `home.file` / `xdg.configFile` + `mkOutOfStoreSymlink` |
| mac dotfile dirs | 6 (borders/karabiner/raycast/ssh/vscode/zsh) | `home.file` + `nix-darwin` モジュール |
| linux dotfile dirs | 2 (ssh/zsh) | `home.file` |
| scripts/ | 69 ファイル (49 .sh + 20 no-ext) | `home.file` (PATH 互換) or `writeShellApplication` |
| install スクリプト総計 | 約 6,505 行 | `flake.nix` + `home.nix` + `darwin.nix` で数百行に圧縮見込み |

## 2. アーキテクチャ

### ディレクトリ構成 (移行後)

```
~/dotfiles/
├── flake.nix                 # entrypoint。inputs (nixpkgs, home-manager, nix-darwin)、outputs
├── flake.lock                # 全 input のバージョン固定
├── nix/
│   ├── hosts/
│   │   ├── shonenm.nix       # mac (M-series) の host 設定
│   │   ├── linux-sudo.nix    # Linux sudo 環境
│   │   └── linux-rootless.nix # sudoless Linux (nix-portable or nix-user-chroot 経由)
│   ├── modules/
│   │   ├── packages/
│   │   │   ├── core.nix      # 全環境共通 (zsh, tmux, git, fd, rg, eza, bat, fzf, ...)
│   │   │   ├── mac.nix       # mac-only (sketchybar, aerospace, ...)
│   │   │   └── linux.nix     # linux-only
│   │   ├── programs/
│   │   │   ├── zsh.nix       # programs.zsh.* で sheldon, atuin, abbr 統合
│   │   │   ├── tmux.nix
│   │   │   ├── starship.nix
│   │   │   ├── git.nix
│   │   │   └── neovim.nix
│   │   ├── dotfiles.nix      # home.file の宣言群 (mkOutOfStoreSymlink で mutable 維持)
│   │   ├── scripts.nix       # scripts/ → PATH 化 (home.file ベース)
│   │   ├── claude.nix        # Claude harness symlinks (mutable 領域は ignore)
│   │   └── darwin/
│   │       ├── system.nix    # defaults write 系を nix-darwin で宣言
│   │       ├── homebrew.nix  # cask のみ (1password-cli, ghostty, raycast, ...)
│   │       └── services.nix  # launchd, sketchybar 自動起動
│   └── overlays/
│       ├── default.nix       # overlay 集約
│       ├── genshijin.nix     # nixpkgs に無いツール (要 sha256)
│       ├── dops.nix
│       ├── quay.nix
│       └── lemonade.nix      # 既に GitHub release から install してるもの
├── common/, mac/, linux/     # ← 既存 stow ツリー (移行完了まで併存、最終的に削除)
├── scripts/                  # ← 維持。`home.file` でリンクして PATH 化
├── install.sh                # ← 移行完了まで保持。最終的に bootstrap-nix.sh に置換
└── docs/
    └── nix-migration-plan.md # この計画書
```

### Flake 出力構造

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
    nix-darwin = { url = "github:LnL7/nix-darwin"; inputs.nixpkgs.follows = "nixpkgs"; };
  };
  outputs = { ... }: {
    darwinConfigurations.shonenm = nix-darwin.lib.darwinSystem { ... };
    homeConfigurations."matsushimakouta@linux-sudo" = home-manager.lib.homeManagerConfiguration { ... };
    homeConfigurations."matsushimakouta@linux-rootless" = ...;
  };
}
```

## 3. 前提条件検証 (Phase 0 で実施)

### 3.1 mac 側
- [ ] Determinate Nix Installer (推奨) または公式 multi-user installer で Nix install
- [ ] `nix --version` ≥ 2.18
- [ ] `nix flake show github:nix-community/home-manager` が通る
- [ ] 既存 Homebrew は併存可 (nix-darwin の `homebrew` module で declarative に統合)

### 3.2 Linux sudo 側 (リモート開発機)
- [ ] `unshare --user --pid echo ok` が通る (user namespaces 有効)
- [ ] `/nix` への write 権限取得可 (root 1回限り)
- [ ] systemd の有無確認 (daemon mode に影響)

### 3.3 Linux sudoless 側 (locked-down hosts、現 pixi 領域)
- [ ] 各 rcon ターゲットで `unshare --user --pid echo ok` を実行 → 結果マトリクス作成
- [ ] 結果 A (user namespaces 可): nix-user-chroot 採用
- [ ] 結果 B (user namespaces 不可): nix-portable + proot 受容 or pixi 残置を許容
- [ ] 結果次第で 「Linux sudoless は当面 pixi 維持」も選択肢

DECISION 1: sudoless ホストが極小数 (1〜2台) なら、その台のみ pixi 残置で OK か？

## 4. Phase 計画

各 phase は独立 PR 化。前 phase が動いている状態を保ったまま積み上げる。

### Phase 0: 前提検証 + scaffold (1〜2 日)
- 上記 3 の前提検証マトリクス作成
- `flake.nix` 雛形 + `nix/` ディレクトリ作成
- `direnv` + `nix develop` で `nix` コマンドへの導線確保
- 既存 install.sh は無変更

検証: `nix flake check` が通る。空 flake で `nix build .#darwinConfigurations.shonenm.system` が成功。

### Phase 1: mac packages 移行 (3〜5 日)
- `nix/modules/packages/core.nix` 作成
- `config/Brewfile` の formulae を Nix package に対応 (約 80 個、ほぼ全部 nixpkgs にあり)
- nixpkgs に無いもの (lemonade, dops, quay, keifu, genshijin 等) を `overlays/` に書く
- cask は `nix-darwin` の `homebrew.casks` に残す (1password CLI, ghostty, raycast, karabiner-elements, ...)
- mise tools は当面そのまま (DECISION 2 で扱い決定)
- 既存 Brewfile も残置 (両方インストール可能だが、Nix を正とする)

検証: `darwin-rebuild switch --flake .` が成功し `which fd` が `/nix/store/...` を返す。
旧 stow 構成は無変更。

### Phase 2: mac dotfiles 移行 (3〜5 日)
- `home.file` / `xdg.configFile` で `common/*` を順次 import
- mutable 領域 (Claude `projects/sessions/cache`, Codex 同等) は `mkOutOfStoreSymlink` で実ファイルへの絶対 symlink、または home-manager 管理外
- `programs.zsh.*`, `programs.tmux.*`, `programs.starship.*` で sheldon, atuin, abbr を統合 (生 dotfile から宣言式に変換するかは選択可)
- `scripts/` を `home.file."bin/<name>" = { source = ../scripts/<name>; executable = true; }` で PATH 化
- 旧 stow link は順次外す (各 dir 完了ごとに `stow -D`)

検証: tmux/neovim/zsh の挙動が移行前と同一。`/Users/matsushimakouta/scripts` PATH が無くなり `~/.nix-profile/bin/beacon` 等で解決する。

DECISION 2: `programs.zsh` / `programs.tmux` の宣言式変換まで踏むか、それとも `home.file` symlink (現生ファイル維持) に留めるか?
- 宣言式: 完全 Nix native、再現性高、しかし dotfiles の構造変化が大きい
- symlink 維持: 移行コスト最小、現生ファイルそのまま、しかし Nix の恩恵小

### Phase 3: mac system 設定移行 (2〜4 日)
- `nix-darwin` の `system.defaults.*` で macOS preferences を宣言化
- aerospace, karabiner, sketchybar の起動設定を `launchd` 経由で宣言
- `/etc/zshrc` 系の触りどころは nix-darwin の `programs.zsh.enable` に委譲

検証: 新規 mac での clone → 1 コマンド (`darwin-rebuild switch`) で全 GUI 設定が復元できること。

### Phase 4: Linux sudo path 移行 (3〜5 日)
- `homeConfigurations."matsushimakouta@linux-sudo"` 作成
- `nix/modules/packages/linux.nix` で apt パッケージのうち Nix 化可能なものを Nix へ
- 系統に無い system-level なもの (postgresql server, fonts) は apt 残置 → ドキュメント化
- `home-manager switch --flake .#matsushimakouta@linux-sudo` 動作確認

検証: リモート開発機で `home-manager switch` が通り、各 CLI ツールが Nix 由来になる。tmux/zsh 挙動同一。

### Phase 5: Linux sudoless path (Phase 0 結果次第)
3.3 の結果マトリクスに基づき分岐:
- ケース A (user namespaces 可): nix-user-chroot 経由で同じ `homeConfigurations` 適用
- ケース B (user namespaces 不可): nix-portable + proot で必要最小ツールのみ、または pixi 残置許容
- 影響範囲が小さければ pixi 残置を正式採用 (config/pixi-packages.txt 維持)

検証: 該当ターゲットで主要 CLI が動く。ralph-crew, rcon, tmux 接続が無傷。

### Phase 6: 旧構成の段階削除 (1〜2 日)
- Phase 2〜5 完了後、`stow -D` 完了済みパッケージから順に `common/<pkg>/` ディレクトリを削除 (内容は `nix/` 側に移動済みなので消える)
- `install.sh` を Nix bootstrap 専用に書き換え (1Password CLI 確認 → Determinate Nix install → `nix run .#bootstrap` の 3 ステップに圧縮)
- `scripts/mac.sh` / `scripts/linux.sh` の install\_\* 関数を削除 (Nix が代替)
- `config/Brewfile` 残置 (cask 用)、`config/packages.linux.apt.txt` 残置 (Nix 化不可分のみ)
- `config/pixi-packages.txt` は Phase 5 結果次第

検証: clean mac で `git clone && ./install.sh` が全部復元する。

### Phase 7: container / Docker worktree 対応 (オプション、2〜3 日)
- 現 `install-in-container.sh` を保持するか、container 用に軽量 `nix-portable` 戦略へ切替えるかを判断
- ralph-crew が container 内で動く前提を維持

DECISION 3: container 側も Nix 化するか、container は現状維持で外部のみ Nix 化するか?

## 5. リスクと緩和

| リスク | 影響 | 緩和 |
|--------|-----|------|
| Nix 学習コスト過小評価で停滞 | 移行 1〜2ヶ月延長 | Phase 1 (packages のみ) で 1 週間以内に体感メリット確認、ダメなら撤退判定 |
| nix-darwin と既存 brew の衝突 | 環境破損 | nix-darwin は brew を declarative に管理可能。並行運用期間中は両方インストールを許容 |
| 1Password CLI / 認証フロー破綻 | 開発不能 | 1Password CLI は nixpkgs にあり (`_1password-cli`)。設定は templates/ 流用 |
| Claude harness 破損 | AI 作業不能 | mutable 領域は `mkOutOfStoreSymlink` で絶対 symlink、stow と完全同等 |
| sudoless host で Nix install 不可 | 一部リモート不能 | Phase 0 で検証、ダメなら pixi 残置を正式採用 |
| ralph-crew / rcon フロー破壊 | 自律ワーカー停止 | scripts/ は `home.file` で PATH 互換維持、tmux session 設計は不変 |
| flake update で破壊的変更 | 突然壊れる | `flake.lock` で固定、`nix flake update` は意図したタイミングのみ |

## 6. 撤退条件

以下のいずれかで Phase 0 終了後に中止判定:
- Phase 0 検証で sudoless / container path に解が無く、Linux 全体の体験劣化が見込まれる場合
- Phase 1 完了時点で日常操作速度が許容範囲を超えて遅い場合
- nixpkgs / overlay で網羅できないツール (Claude Code 自体や Claude プラグイン等) が運用上致命的になった場合

## 7. 即時の決定事項

実装着手前に下記を確定する:

- DECISION 1: sudoless ホストの台数とポリシー (Phase 0 検証後)
- DECISION 2: dotfiles を `programs.*` 宣言式に変換するか、`home.file` symlink に留めるか (Phase 2 着手前)
- DECISION 3: container 側も Nix 化するか (Phase 7 要否)
- DECISION 4: mise tools を Nix に統合するか維持するか
- DECISION 5: Nix installer は Determinate Systems 版 / 公式 multi-user / 公式 single-user のどれを採用するか

## 8. タイムライン目安

| Phase | 所要 | 累計 |
|-------|------|------|
| 0. 前提検証 + scaffold | 1〜2 日 | 2 日 |
| 1. mac packages | 3〜5 日 | 7 日 |
| 2. mac dotfiles | 3〜5 日 | 12 日 |
| 3. mac system | 2〜4 日 | 16 日 |
| 4. Linux sudo | 3〜5 日 | 21 日 |
| 5. Linux sudoless | 2〜4 日 | 25 日 |
| 6. 旧構成削除 | 1〜2 日 | 27 日 |
| 7. container (任意) | 2〜3 日 | 30 日 |

実工数換算で 3〜4 週間。日常作業と並行なら 6〜8 週間が現実線。
