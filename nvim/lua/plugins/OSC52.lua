-- lazy.nvimを使ってる場合
return {
    "ojroques/nvim-osc52",
    config = function()
      require("osc52").setup {
        max_length = 0,        -- 0 = no limit
        trim = false,
        silent = false,
      }
  
      -- `y` でクリップボードコピーできるようにマッピング
      local function copy()
        require("osc52").copy_register("+")
      end
  
      vim.keymap.set("n", "<leader>c", copy)
      vim.keymap.set("v", "<leader>c", copy)
    end
  }
  