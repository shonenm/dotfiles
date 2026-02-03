return {
  "mfussenegger/nvim-lint",
  opts = function(_, opts)
    opts.linters_by_ft = {
      -- cspell for code spell checking (requires: npm install -g cspell)
      typescript = { "cspell" },
      typescriptreact = { "cspell" },
      javascript = { "cspell" },
      javascriptreact = { "cspell" },
      python = { "cspell" },
      markdown = { "cspell" },
    }

    -- Downgrade cspell to HINT severity (underline only, no inline diagnostic text)
    local cspell = require("lint").linters.cspell
    local orig_parser = cspell.parser
    cspell.parser = function(output, bufnr, linter_cwd)
      local diagnostics = orig_parser(output, bufnr, linter_cwd)
      for _, d in ipairs(diagnostics) do
        d.severity = vim.diagnostic.severity.HINT
      end
      return diagnostics
    end
  end,
}
