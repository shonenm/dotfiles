# dotfiles

macOS / Linux の開発環境設定を GNU Stow で管理する。

## 構成

- `common/` — 共通設定
- `mac/` / `linux/` — OS 固有設定
- `config/` — パッケージ・ツールの宣言
- `scripts/` — インストーラーとユーザー向けコマンド
- `docs/` — 利用手順と設計資料
- `install.sh` — 全環境共通の入口

## 開発原則

- 対症療法ではなく根本原因を修正する。
- 変更は `install.sh` から再現できる状態に保つ。
- macOS / Linux / no-sudo のうち影響する経路を同時に更新する。OS 固有機能は、他OSへ無理に追加せず対象範囲を文書化する。
- シェル起動時の処理は遅延ロードし、不要なサブシェルを増やさない。
- 既存実装と正本を確認してから変更し、生成物やランタイムファイルを直接編集しない。

## 新しいツールの登録先

取得方式ごとの正本は [新環境セットアップ](docs/install/setup-new-environment.md#新ツール追加時の登録先) を参照する。`scripts/mac.sh` / `scripts/linux.sh` に個別パッケージを直書きしない。

## scripts/ 命名規約

`~/dotfiles/scripts` は PATH に含まれる。

- ユーザー向けコマンド: 拡張子なし（例: `dotsync`, `claude-gc`, `beacon`）
- ライブラリ: `-lib.sh`（例: `ralph-lib.sh`）
- tmux・hook・内部処理: `.sh`

## ドキュメント

- 変更に関連する文書を同じコミットで更新する。
- `README.md` は概要と入口、`docs/INDEX.md` は文書一覧、詳細は各カテゴリに置く。
- 現行手順、設計仕様、日付付き計画・レビューを混在させない。
- 説明文は日本語を基本とし、コマンド、パス、API名、公式製品名は原表記を維持する。

## Stow

設定は実際のホームディレクトリ構造をパッケージ配下に再現する。

```bash
mkdir -p common/<tool>/.config/<tool>
stow -d common -t ~ --no-folding <tool>
```

認証情報、キャッシュ、履歴などのランタイムファイルは `.stow-local-ignore` とパッケージ内 `.gitignore` で除外する。

## 検証

変更前後で関連テストに加え、少なくとも次を実行する。

```bash
scripts/check-markdown-links.py
scripts/check-package-duplication.sh
```

merge / rebase のコンフリクト解決は `/d-conflict-resolve` を使用する。
