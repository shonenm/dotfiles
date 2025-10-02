return {
  {
    "Wansmer/treesj",
    dependencies = { "nvim-treesitter" },
    config = function()
      require("treesj").setup({
        use_default_keymaps = false, -- デフォルトのキーマッピングを無効化
        max_join_length = 120, -- 結合時の最大文字数
      })

      -- キーマッピング設定
      vim.api.nvim_set_keymap("n", "<leader>tsj", ":TSJToggle<CR>", { noremap = true, silent = true })
    end,
  },
}
