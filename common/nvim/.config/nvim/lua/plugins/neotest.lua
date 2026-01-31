return {
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/neotest-jest",
      "marilari88/neotest-vitest",
      "nvim-neotest/neotest-python",
      "thenbe/neotest-playwright",
    },
    opts = {
      adapters = {
        ["neotest-jest"] = {
          jestCommand = "npx jest",
          -- Monorepo support: detect nearest package.json as root
          cwd = function(path)
            local util = require("lspconfig.util")
            return util.root_pattern("package.json", "jest.config.ts", "jest.config.js")(path)
              or vim.fn.getcwd()
          end,
          jestConfigFile = function(file)
            local util = require("lspconfig.util")
            local root = util.root_pattern("jest.config.ts", "jest.config.js")(file)
            if root then
              local ts_config = root .. "/jest.config.ts"
              if vim.fn.filereadable(ts_config) == 1 then
                return ts_config
              end
              return root .. "/jest.config.js"
            end
            return nil
          end,
        },
        ["neotest-vitest"] = {},
        ["neotest-python"] = {
          runner = "pytest",
          python = function()
            local venv = os.getenv("VIRTUAL_ENV")
            if venv then
              return venv .. "/bin/python"
            end
            -- uv managed venv fallback
            if vim.fn.filereadable(".venv/bin/python") == 1 then
              return ".venv/bin/python"
            end
            return "python"
          end,
          args = { "-vv", "--tb=short" },
        },
        ["neotest-playwright"] = {
          options = {
            enable_dynamic_test_discovery = true,
          },
        },
      },
      consumers = {
        overseer = require("neotest.consumers.overseer"),
      },
      output = { open_on_run = true },
      output_panel = { open = "botright split | resize 15" },
    },
  },
  { "nvim-neotest/neotest-jest", lazy = true },
  { "marilari88/neotest-vitest", lazy = true },
  { "nvim-neotest/neotest-python", lazy = true },
  { "thenbe/neotest-playwright", lazy = true },
}
