return {
  -- JS/TS debug adapter (vscode-js-debug)
  {
    "mxsdev/nvim-dap-vscode-js",
    dependencies = {
      "mfussenegger/nvim-dap",
      {
        "microsoft/vscode-js-debug",
        build = "npm install --legacy-peer-deps && npx gulp vsDebugServerBundle && mv dist out",
        version = "1.*",
      },
    },
    config = function()
      local dap = require("dap")

      require("dap-vscode-js").setup({
        debugger_path = vim.fn.stdpath("data") .. "/lazy/vscode-js-debug",
        adapters = { "pwa-node", "pwa-chrome" },
      })

      -- Node.js / TypeScript configurations
      for _, language in ipairs({ "typescript", "javascript", "typescriptreact", "javascriptreact" }) do
        dap.configurations[language] = {
          -- Attach to Docker container (BFF: port 9229)
          {
            type = "pwa-node",
            request = "attach",
            name = "Attach to Docker (port 9229)",
            port = 9229,
            localRoot = "${workspaceFolder}",
            remoteRoot = "/app",
            sourceMaps = true,
            skipFiles = { "<node_internals>/**" },
          },
          -- Launch current file
          {
            type = "pwa-node",
            request = "launch",
            name = "Launch Current File",
            program = "${file}",
            cwd = "${workspaceFolder}",
            sourceMaps = true,
            skipFiles = { "<node_internals>/**" },
          },
          -- Launch with ts-node
          {
            type = "pwa-node",
            request = "launch",
            name = "Launch with ts-node",
            runtimeExecutable = "npx",
            runtimeArgs = { "ts-node" },
            program = "${file}",
            cwd = "${workspaceFolder}",
            sourceMaps = true,
          },
        }
      end
    end,
  },
}
