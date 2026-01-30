-- Python: Ruff formatter + Mypy type checker + basedpyright extraPaths
return {
  -- Ruff as Python formatter via conform.nvim
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        python = { "ruff_organize_imports", "ruff_format" },
      },
    },
  },
  -- Mypy as Python type checker via nvim-lint
  {
    "mfussenegger/nvim-lint",
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.python = opts.linters_by_ft.python or {}
      table.insert(opts.linters_by_ft.python, "mypy")
    end,
  },
  -- basedpyright: extra analysis paths for monorepo agent directories
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        basedpyright = {
          settings = {
            basedpyright = {
              analysis = {
                extraPaths = {
                  "agents/core",
                  "agents/topics",
                  "agents/topics-experimental",
                },
              },
            },
          },
        },
      },
    },
  },
}
