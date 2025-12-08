return {
  "nvim-neo-tree/neo-tree.nvim",
  branch = "v3.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-web-devicons",
    "MunifTanjim/nui.nvim",
  },
  config = function()
    require("neo-tree").setup({
      filesystem = {
        filtered_items = {
          visible = true, -- 非表示ファイルもグレー表示
          hide_dotfiles = false, -- ドットファイルを表示（.env, .gitignoreなど）
          hide_gitignored = false, -- gitignore されたファイルも表示
          hide_by_name = {
            "node_modules",
            ".DS_Store",
          },
          hide_by_pattern = {
            "*.log",
            "*.tmp",
          },
        },
      },
    })
  end,
}
