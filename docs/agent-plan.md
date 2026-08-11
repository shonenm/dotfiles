# Pi UI shell prototype plan

> **由来:** **Custom** Pi UI shellの実装計画（[区分](provenance.md#区分)）

- [x] `statusline.ts`を単一UI ownerへ拡張し、header・editor・footer・working indicator・tab titleを統合する。
- [x] 既存3段telemetryを保持しつつ、幅とprofileに応じたresponsive表示と`/status`詳細overlayを追加する。
- [x] 競合するpackage UI、重複permission、working message tickerをfilterし、Pi Studio・extmgrなど重複しない機能は残す。
- [x] Pi実起動、overlay、Markdown link・package duplication checkで検証する。
