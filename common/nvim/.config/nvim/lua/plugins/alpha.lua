return {
  -- snacks.nvim の dashboard を無効化
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = { enabled = false },
    },
  },

  -- alpha-nvim のヘッダーをカスタマイズ
  {
    "goolord/alpha-nvim",
    dependencies = {
      { "MaximilianLloyd/ascii.nvim", dependencies = { "MunifTanjim/nui.nvim" } },
    },
    opts = function(_, dashboard)
      local ascii = require("ascii")
      local config_path = vim.fn.stdpath("config")

      -- art.txt を読み込み
      local function read_file(path)
        local lines = {}
        local file = io.open(path, "r")
        if file then
          for line in file:lines() do
            table.insert(lines, line)
          end
          file:close()
        end
        return lines
      end

      local art = read_file(config_path .. "/assets/art.txt")

      -- art + ascii.nvim の sharp デザインを結合
      local logo = {}
      for _, line in ipairs(art) do
        table.insert(logo, line)
      end
      for _, line in ipairs(ascii.art.text.neovim.sharp) do
        table.insert(logo, line)
      end

      dashboard.section.header.val = logo
      return dashboard
    end,
  },
}
