return {
  "mfussenegger/nvim-lint",
  opts = {
    linters_by_ft = {
      -- cspell for code spell checking (requires: npm install -g cspell)
      typescript = { "cspell" },
      typescriptreact = { "cspell" },
      javascript = { "cspell" },
      javascriptreact = { "cspell" },
      python = { "cspell" },
      markdown = { "cspell" },
    },
  },
}
