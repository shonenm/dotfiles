return {
  {
    "monaqa/dial.nvim",
    config = function()
      local augend = require("dial.augend")

      require("dial.config").augends:register_group({
        -- ノーマルモードとビジュアルモード用
        default = {
          augend.integer.alias.decimal, -- 整数のインクリメント/デクリメント
          augend.integer.alias.hex, -- 16進数のインクリメント/デクリメント
          augend.date.alias["%Y/%m/%d"], -- 日付（YYYY/MM/DD）のインクリメント/デクリメント
          augend.constant.alias.bool, -- true/false の切り替え
        },
      })

      -- キーマッピング設定
      vim.api.nvim_set_keymap("n", "<C-a>", require("dial.map").inc_normal(), { noremap = true, silent = true })
      vim.api.nvim_set_keymap("n", "<C-x>", require("dial.map").dec_normal(), { noremap = true, silent = true })
    end,
  },
}
