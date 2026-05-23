# codediff.nvim: Virtual buffer シンタックスハイライト修復

- **ファイル**: `common/nvim/.config/nvim/lua/plugins/codediff.lua`
- **対象**: `esmuellert/codediff.nvim` - `codediff/core/virtual_file.lua`
- **症状**: Explorer mode でPythonファイルの変更前(左側/virtual buffer)が完全にモノクロ表示になる。TypeScriptでは両側正常にハイライトされる
- **原因**: virtual bufferのハイライトは3層構造(treesitter / vim syntax / semantic tokens)だが、Pythonではtreesitterが起動しても描画されない場合がある。TypeScriptではsemantic tokensが豊富なハイライトを提供するため問題が顕在化しない
- **対処**: `CodeDiffVirtualFileLoaded` autocmdで treesitterの状態を検証し、アクティブなら `nvim__redraw` で強制再描画、非アクティブなら `parse_url` からfilepathを取得してリトライ、それも失敗したらvim syntaxにフォールバック
- **削除条件**: codediff.nvim upstream の `load_virtual_buffer_content` でtreesitterハイライトの確実な初期化が実装されたら削除
