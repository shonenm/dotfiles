return {
  {
    "ahmedkhalf/project.nvim",
    event = "VimEnter",
    config = function()
      require("project_nvim").setup({
        manual_mode = false, -- 自動でプロジェクトを検出
        detection_methods = { "lsp", "pattern" }, -- プロジェクトの検出方法
        patterns = { ".git", "Makefile", "package.json" }, -- プロジェクトのルートとして認識するファイル/フォルダ
        show_hidden = false,
        silent_chdir = true, -- ディレクトリ変更時に通知を無効化
        scope_chdir = "global",
      })

      require("telescope").load_extension("projects")
    end,
  },
}
