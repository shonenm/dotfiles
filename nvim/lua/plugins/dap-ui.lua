return {
  "rcarriga/nvim-dap-ui",
  dependencies = { "mfussenegger/nvim-dap" },
  config = function()
    local dap, dapui = require("dap"), require("dapui")

    dapui.setup()

    -- DAP イベントに応じて UI を自動開閉
    dap.listeners.after.event_initialized["dapui_config"] = function()
      dapui.open()
    end
    dap.listeners.before.event_terminated["dapui_config"] = function()
      dapui.close()
    end
    dap.listeners.before.event_exited["dapui_config"] = function()
      dapui.close()
    end

    vim.keymap.set("n", "<Leader>du", dapui.toggle, { desc = "DAP UI: Toggle" })
  end,
}
