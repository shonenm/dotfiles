# Zshパフォーマンス最適化

> **由来:** **Upstream** Zsh・mise・direnv・Starship / **Plugin** Sheldon導入plugin / **Configuration** startup・hook・cache設定（[区分](../provenance.md#区分)）

Zshの起動時間だけでなく、prompt表示とdirectory移動の継続コストを抑えるための現行仕様。

## 現在の計測値

macOS arm64、Zsh 5.9で`hyperfine --warmup 3 --runs 15`を使用した結果。

| 対象 | 平均 |
|---|---:|
| interactive non-login shell (`zsh -ic exit`) | 約200ms |
| interactive login shell (`zsh -lic exit`) | 約227ms |
| Starship prompt（Git repository内） | 約23ms |
| Starship prompt（`git_metrics`なしとの比較） | 約2ms増 |

shell起動時間にはmiseの初回environment解決が含まれる。prompt後に遅延実行されるpluginや、通常のコマンド実行中に走るhookは別に確認する。

## Startup構成

### PATH

`.zshenv`を非interactive shellを含むPATH設定の正本とする。

```zsh
typeset -U path PATH
```

Zshのtied arrayをunique化し、nested shellやstartup fileの再読込で同じPATH要素が蓄積するのを防ぐ。`~/.pixi/bin`、`~/.local/bin`、`~/dotfiles/scripts`は`.zshrc.common`で重ねて追加しない。pnpmとPythonはmise管理のPATHを使用する。

### Completion

すべての`fpath`を追加した後、`.zshrc`末尾で`compinit`を一度だけ実行する。

- `.zcompdump`が24時間より古い、または存在しない: `compinit`
- それ以外: `compinit -C`

静的な補完は`~/.zsh/completions`へ置く。毎回CLIから補完scriptを生成しない。

### Sheldon plugins

Sheldonが次を管理する。

- `zsh-completions`: `fpath`のみ追加
- `zsh-abbr`: startup時に直接読込
- `forgit`, `zsh-syntax-highlighting`, `zsh-autosuggestions`: `zsh-defer`でprompt表示後に読込

`zsh-abbr`自身が`$ABBR_USER_ABBREVIATIONS_FILE`を読み込むため、OS別`.zshrc.local`から`abbr import`を重ねて実行しない。

## 継続コストの制御

### mise

`mise activate zsh`は使わず、shims directoryをPATHに追加するshims方式を採用する。

```zsh
[[ -d "$HOME/.local/share/mise/shims" ]] && export PATH="$HOME/.local/share/mise/shims:$PATH"
```

理由: activate方式（hook-env）はPATHにバージョン固定のinstall directoryを焼き込むため、tool更新が既存シェルに反映されない。反映にはpromptごとの`precmd` hook（外部process起動でfork コストが高い）か、更新経路ごとのラッパー（`dots`のみラップしていたため`mise up`直接実行で漏れた）が必要だった。shimは実行時に現在バージョンを解決するため、precmdゼロコストで更新が即反映され、projectごとのtool切替もexec時に効く。

トレードオフ: mise configの`[env]`セクションによる環境変数注入は効かない（env注入はdirenvで行う）。tool実行ごとにshim経由の小さな解決コストが乗る。

### Starship

Git差分は独自shell scriptではなく、Starship組み込みの`git_metrics`を使用する。

```toml
[git_metrics]
disabled = false
only_nonzero_diffs = true
```

`git_status`と並列に評価され、追加・削除行数を表示する。差分ファイル数は表示しない。

### Directory移動

次のhookは用途があるため維持する。

- mise: project tool切替
- direnv: `.envrc`反映
- zoxide: directory履歴記録
- `chpwd() { ls }`: directory移動後の一覧表示

自動`ls`は大きなdirectoryで遅くなる可能性があるが、現在は操作性を優先して残している。

### rip graveyard

shell起動時にはgraveyardを走査しない。30日を超えた項目は必要なときだけ削除する。

```bash
graveyard-purge
```

## Login shell

macOSのlogin shellではHomebrewの環境を設定する。

```zsh
eval "$(/opt/homebrew/bin/brew shellenv)"
```

tmux paneはnon-login Zshを起動するため、pane作成ごとには実行されない。PythonのPATHはmiseへ統一し、固定versionのFramework PATHは追加しない。

## 計測

```bash
hyperfine --warmup 3 --runs 15 'zsh -ic exit' 'zsh -lic exit'
starship timings

# cached compinitを含むfunction profile
zsh -dfi -c 'zmodload zsh/zprof; source ~/.zshrc; zprof'
```

起動速度だけを改善して処理を毎コマンドへ移さないよう、startup、prompt、`cd`、tool実行を分けて比較する。
