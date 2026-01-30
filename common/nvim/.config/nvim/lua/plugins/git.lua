return {
  -- vim-fugitive: Git操作のデファクトスタンダード
  {
    "tpope/vim-fugitive",
    cmd = { "Git", "Gstatus", "Gdiff", "Gblame", "Gwrite", "Gread" },
    keys = {
      { "<leader>gs", "<cmd>Git<cr>", desc = "Git Status" },
      { "<leader>gb", "<cmd>Git blame<cr>", desc = "Git Blame" },
    },
  },

  -- toggleterm.nvim: lazygit/lazydocker連携用ターミナル
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    keys = {
      {
        "<leader>gg",
        function()
          local Terminal = require("toggleterm.terminal").Terminal
          local lazygit = Terminal:new({
            cmd = "lazygit",
            dir = "git_dir",
            direction = "float",
            float_opts = {
              border = "rounded",
              width = function()
                return math.floor(vim.o.columns * 0.9)
              end,
              height = function()
                return math.floor(vim.o.lines * 0.9)
              end,
            },
            on_open = function(term)
              vim.cmd("startinsert!")
              -- lazygit内でのEscを有効にする
              vim.api.nvim_buf_set_keymap(term.bufnr, "t", "<Esc>", "<Esc>", { noremap = true, silent = true })
            end,
            on_close = function(_)
              vim.cmd("startinsert!")
            end,
          })
          lazygit:toggle()
        end,
        desc = "Lazygit",
      },
      {
        "<leader>od",
        function()
          local Terminal = require("toggleterm.terminal").Terminal
          local lazydocker = Terminal:new({
            cmd = "lazydocker",
            direction = "float",
            float_opts = {
              border = "rounded",
              width = function()
                return math.floor(vim.o.columns * 0.9)
              end,
              height = function()
                return math.floor(vim.o.lines * 0.9)
              end,
            },
            on_open = function(term)
              vim.cmd("startinsert!")
              vim.api.nvim_buf_set_keymap(term.bufnr, "t", "<Esc>", "<Esc>", { noremap = true, silent = true })
            end,
          })
          lazydocker:toggle()
        end,
        desc = "Lazydocker",
      },
    },
    opts = {
      size = 20,
      open_mapping = [[<c-\>]],
      hide_numbers = true,
      shade_filetypes = {},
      shade_terminals = true,
      shading_factor = 2,
      start_in_insert = true,
      insert_mappings = true,
      persist_size = true,
      direction = "float",
      close_on_exit = true,
      shell = vim.o.shell,
      float_opts = {
        border = "rounded",
        winblend = 0,
      },
    },
  },
}
