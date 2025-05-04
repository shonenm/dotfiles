return {
  "mfussenegger/nvim-dap",
  config = function()
    local dap = require("dap")

    -- キーバインド
    vim.keymap.set("n", "<F5>", dap.continue, { desc = "DAP: Continue" })
    vim.keymap.set("n", "<F10>", dap.step_over, { desc = "DAP: Step Over" })
    vim.keymap.set("n", "<F11>", dap.step_into, { desc = "DAP: Step Into" })
    vim.keymap.set("n", "<F12>", dap.step_out, { desc = "DAP: Step Out" })
    vim.keymap.set("n", "<Leader>b", dap.toggle_breakpoint, { desc = "DAP: Toggle Breakpoint" })
    vim.keymap.set("n", "<Leader>B", function()
      dap.set_breakpoint(vim.fn.input("Breakpoint condition: "))
    end, { desc = "DAP: Set Conditional Breakpoint" })
  end,
}

