return {
  -- vim-dadbod-ui: Database UI for Neovim
  {
    "kristijanhusak/vim-dadbod-ui",
    dependencies = {
      "tpope/vim-dadbod",
      "kristijanhusak/vim-dadbod-completion",
    },
    cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
    keys = {
      { "<leader>db", "<cmd>DBUIToggle<cr>", desc = "DBUI Toggle" },
      { "<leader>df", "<cmd>DBUIFindBuffer<cr>", desc = "DBUI Find Buffer" },
      { "<leader>dl", "<cmd>DBUILastQueryInfo<cr>", desc = "DBUI Last Query Info" },
    },
    init = function()
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_show_database_icon = 1
      vim.g.db_ui_force_echo_notifications = 1
      -- 自動実行は無効（大きなクエリの事故防止）
      vim.g.db_ui_execute_on_save = 0
      -- .sql ファイルを保存する場所
      vim.g.db_ui_save_location = vim.fn.stdpath("data") .. "/db_ui"
    end,
  },

  -- blink.cmp: SQL completion via vim-dadbod-completion
  {
    "saghen/blink.cmp",
    optional = true,
    dependencies = { "kristijanhusak/vim-dadbod-completion" },
    opts = {
      sources = {
        default = { "dadbod" },
        providers = {
          dadbod = { name = "Dadbod", module = "vim_dadbod_completion.blink" },
        },
      },
    },
  },

  -- conform.nvim: SQL formatter
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        sql = { "sql_formatter" },
        pgsql = { "sql_formatter" },
      },
      formatters = {
        sql_formatter = {
          prepend_args = { "-l", "postgresql" },
        },
      },
    },
  },

  -- toggleterm.nvim: pgcli/dblab integration
  {
    "akinsho/toggleterm.nvim",
    keys = {
      {
        "<leader>dp",
        function()
          local Terminal = require("toggleterm.terminal").Terminal
          local db_url = vim.env.DATABASE_URL or "postgresql://postgres:postgres@localhost:5432/postgres"
          local pgcli = Terminal:new({
            cmd = "pgcli " .. db_url,
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
          pgcli:toggle()
        end,
        desc = "pgcli",
      },
      {
        "<leader>de",
        function()
          local Terminal = require("toggleterm.terminal").Terminal
          local db_url = vim.env.DATABASE_URL or "postgresql://postgres:postgres@localhost:5432/postgres"
          local dblab = Terminal:new({
            cmd = "dblab --url " .. db_url,
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
          dblab:toggle()
        end,
        desc = "dblab",
      },
    },
  },
}
