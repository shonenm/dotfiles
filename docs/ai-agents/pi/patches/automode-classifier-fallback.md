# pi-automode: classifier fallback

> **由来:** **Plugin** `@czottmann/pi-automode` / **Local patch** カンマ区切りclassifier fallback（[区分](../../../provenance.md#区分)）

- **ファイル**: `scripts/patch-pi-automode.sh`
- **対象**: `@czottmann/pi-automode` 1.11.0 の `extensions/auto-mode/classifier.ts`
- **症状**: `classifierModel` が1つしか使えず、認証切れやquota障害で全toolが fail-closed になる
- **原因**: 公式は `autoMode.classifierModel` を単一文字列として解決し、認証失敗時に次候補へ倒さない
- **対処**: カンマ区切りのモデルを順に試し、認証・quota・API key障害のときだけ次へ倒す。policy blockはそのまま fail-closed
- **削除条件**: upstream が複数classifierまたはfallbackをサポートしたら削除
