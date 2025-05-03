return {
    {
      "mfussenegger/nvim-dap",
      dependencies = {
        "rcarriga/nvim-dap-ui",
        "jay-babu/mason-nvim-dap.nvim",
        "williamboman/mason.nvim",
      },
      config = function()
        local dap = require("dap")
        local dapui = require("dapui")
  
        -- UI 設定
        dapui.setup()
  
        -- DAP UI と DAP の連動
        dap.listeners.after.event_initialized["dapui_config"] = function()
          dapui.open()
        end
        dap.listeners.before.event_terminated["dapui_config"] = function()
          dapui.close()
        end
        dap.listeners.before.event_exited["dapui_config"] = function()
          dapui.close()
        end
  
        -- mason-dap を初期化
        require("mason-nvim-dap").setup({
          automatic_setup = true,
          handlers = {},
        })
  
        -- キーバインド例（必要に応じて追加）
        vim.keymap.set("n", "<F5>", function() dap.continue() end)
        vim.keymap.set("n", "<F10>", function() dap.step_over() end)
        vim.keymap.set("n", "<F11>", function() dap.step_into() end)
        vim.keymap.set("n", "<F12>", function() dap.step_out() end)
        vim.keymap.set("n", "<Leader>b", function() dap.toggle_breakpoint() end)
        vim.keymap.set("n", "<Leader>B", function() dap.set_breakpoint(vim.fn.input("Breakpoint condition: ")) end)
        vim.keymap.set("n", "<Leader>du", function() dapui.toggle() end)
      end,
    },
  }
  