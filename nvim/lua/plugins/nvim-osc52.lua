return {
    "ojroques/nvim-osc52",
    config = function()
      local osc52 = require("osc52")
  
      osc52.setup({
        max_length = 0,      -- 無制限
        trim = false,        -- 改行トリミングしない
        silent = false,      -- 成功時にも通知する
      })
  
      -- ノーマルモードでカレント行をコピー
      vim.keymap.set("n", "<leader>c", function()
        osc52.copy_register('"')  -- '"': デフォルトレジスタ
      end, { desc = "Copy line to system clipboard" })
  
      -- ビジュアルモードで選択範囲をコピー
      vim.keymap.set("v", "<leader>c", function()
        osc52.copy_register('"')
      end, { desc = "Copy selection to system clipboard" })
  
      -- 自動で yank 時に OSC52 送信（オプション）
      local function copy_on_yank()
        if vim.v.event.operator == "y" and vim.v.event.regname == "" then
          osc52.copy_register('"')
        end
      end
  
      vim.api.nvim_create_autocmd("TextYankPost", {
        callback = copy_on_yank,
      })
    end,
  }
  