return {
  "nvim-treesitter/nvim-treesitter-context",
  event = { "BufReadPost", "BufNewFile" },
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  config = function()
    require("treesitter-context").setup({
      enable = true, -- デフォルトで有効
      max_lines = 3, -- ヘッダー最大行数（0 で無制限）
      trim_scope = "outer", -- "inner" または "outer"
      mode = "cursor", -- "cursor" または "topline"
      separator = nil, -- 上下を区切る線を追加したい場合は "-" 等
    })
  end,
}
