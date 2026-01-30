-- Custom DAP configurations (adapters are auto-configured by LazyVim extras)
-- JS/TS: lazyvim.plugins.extras.lang.typescript + dap.core → js-debug-adapter via mason
-- Python: lazyvim.plugins.extras.lang.python + dap.core → debugpy via mason
return {
  {
    "mfussenegger/nvim-dap",
    opts = function()
      local dap = require("dap")

      -- Docker attach configuration for BFF container
      local docker_attach = {
        type = "pwa-node",
        request = "attach",
        name = "Attach to Docker (port 9229)",
        port = 9229,
        localRoot = "${workspaceFolder}",
        remoteRoot = "/app",
        sourceMaps = true,
        skipFiles = { "<node_internals>/**" },
      }

      for _, language in ipairs({ "typescript", "javascript", "typescriptreact", "javascriptreact" }) do
        dap.configurations[language] = dap.configurations[language] or {}
        table.insert(dap.configurations[language], docker_attach)
      end
    end,
  },
}
