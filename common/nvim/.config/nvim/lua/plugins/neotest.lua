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
          cwd = function()
            return vim.fn.getcwd()
          end,
        },
        ["neotest-vitest"] = {},
        ["neotest-python"] = {
          runner = "pytest",
          python = function()
            -- Use venv python if available
            local venv = os.getenv("VIRTUAL_ENV")
            if venv then
              return venv .. "/bin/python"
            end
            return "python"
          end,
        },
        ["neotest-playwright"] = {
          options = {
            enable_dynamic_test_discovery = true,
          },
        },
      },
    },
  },
  { "nvim-neotest/neotest-jest", lazy = true },
  { "marilari88/neotest-vitest", lazy = true },
  { "nvim-neotest/neotest-python", lazy = true },
  { "thenbe/neotest-playwright", lazy = true },
}
