# dotfiles

macOS/Linux両環境で動作する開発環境設定。GNU Stowでシンボリックリンクを管理。

## ディレクトリ構造

- `common/` - 共通設定（Mac/Linux両方で使用）
- `mac/` - macOS専用設定
- `linux/` - Linux専用設定
- `scripts/` - インストール・セットアップスクリプト
- `docs/` - ドキュメント

## 主要ツール設定

| ツール | パス |
|--------|------|
| Neovim | `common/nvim/.config/nvim/` |
| Zsh | `common/zsh/.zshrc.common`, `mac/zsh/.zshrc`, `linux/zsh/.zshrc` |
| Tmux | `common/tmux/.config/tmux/` |
| Starship | `common/starship/.config/starship.toml` |

## 開発ルール

### ポータビリティ（必須）

- 変更は`install.sh`でリモートLinux環境に再現可能であること
- macOS専用機能を追加する場合はLinux版も同時に実装
- 新しいツールは`scripts/mac.sh`と`scripts/linux.sh`の両方に追加

### 問題解決

- 対症療法ではなく根本治療を優先
- ワークアラウンド追加前に根本原因を調査・修正
- ハードコードを避け設定可能な形で実装

### ベストプラクティス

- 変更前にWeb検索で最新のベストプラクティスを調査
- より良いツールやアプローチがあれば提案
- 非推奨の機能や古いパターンを使用しない

### パフォーマンス

- シェル起動時間に影響する変更は最適化を考慮
- 遅延ロード（lazy loading）を活用
- 不要なサブシェル起動を避ける

### ドキュメント

- 変更に関連する`docs/`内のmdファイルを更新
- 新機能には必要に応じてドキュメントを追加
- README.mdとの整合性を保つ

## Stowの使い方

新しい設定を追加する場合:

```bash
# 1. ディレクトリ構造を作成（実際のパスを再現）
mkdir -p common/<tool>/.config/<tool>

# 2. 設定ファイルを配置
# 例: common/tool/.config/tool/config.toml

# 3. Stowでシンボリックリンクを作成
cd ~/dotfiles
stow -d common -t ~ <tool>

# 4. 確認
ls -la ~/.config/<tool>
```

OS固有の設定は`mac/<tool>/`または`linux/<tool>/`に配置。
