-- TypeScript: tsgo (TypeScript 7 native LSP)
-- 選択は config/options.lua の vim.g.lazyvim_ts_lsp = "tsgo" で行う。
-- ここで servers.vtsls = false / servers.tsgo = {} を手書きしてはいけない:
-- LazyVim の typescript extra が「選ばれた 1 つ以外を enabled=false にする」
-- ため、手書きすると opts の適用順の関係で vtsls と tsgo の両方が無効化され、
-- TS バッファに TS 系 LSP が一切 attach しなくなる。
return {}
