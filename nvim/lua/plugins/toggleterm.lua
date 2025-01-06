return {
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    config = function()
      require("toggleterm").setup({
        size = 20,
        open_mapping = [[<C-\>]], -- ターミナルを開くキー
        hide_numbers = true,
        shade_filetypes = {},
        shade_terminals = true,
        shading_factor = 2,
        start_in_insert = true,
        insert_mappings = true,
        terminal_mappings = true,
        persist_size = true,
        direction = "float", -- 'vertical' | 'horizontal' | 'tab' | 'float'
        close_on_exit = true,
        shell = vim.o.shell,
        float_opts = {
          border = "curved",
          winblend = 3,
        },
      })

      -- キーマッピング
      local Terminal = require("toggleterm.terminal").Terminal

      -- lazygit のショートカット
      local lazygit = Terminal:new({ cmd = "lazygit", hidden = true })
      function _LAZYGIT_TOGGLE()
        lazygit:toggle()
      end

      -- Htop のショートカット
      local htop = Terminal:new({ cmd = "htop", hidden = true })
      function _HTOP_TOGGLE()
        htop:toggle()
      end

      -- キーバインド
      vim.api.nvim_set_keymap("n", "<leader>tg", "<cmd>lua _LAZYGIT_TOGGLE()<CR>", { noremap = true, silent = true })
      vim.api.nvim_set_keymap("n", "<leader>th", "<cmd>lua _HTOP_TOGGLE()<CR>", { noremap = true, silent = true })
    end,
  },
}
