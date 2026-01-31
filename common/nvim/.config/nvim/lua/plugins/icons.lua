-- Theme-aware icon configuration
-- Material icon glyphs (via nvim-material-icon-v3) injected into mini.icons
-- lspkind codicons for completion menu
-- ColorScheme-aware highlight group switching

-- Map hex color to nearest MiniIcons highlight group
local hl_palette = {
  MiniIconsAzure = { 0x42, 0xa5, 0xf5 },
  MiniIconsBlue = { 0x51, 0x9a, 0xba },
  MiniIconsCyan = { 0x7f, 0xdb, 0xca },
  MiniIconsGreen = { 0x8d, 0xc1, 0x49 },
  MiniIconsGrey = { 0x4d, 0x5a, 0x5e },
  MiniIconsOrange = { 0xe3, 0x79, 0x33 },
  MiniIconsPurple = { 0xa0, 0x74, 0xc4 },
  MiniIconsRed = { 0xcc, 0x3e, 0x44 },
  MiniIconsYellow = { 0xcb, 0xcb, 0x41 },
}

local function hex_to_rgb(hex)
  hex = hex:gsub("#", "")
  return {
    tonumber(hex:sub(1, 2), 16) or 0,
    tonumber(hex:sub(3, 4), 16) or 0,
    tonumber(hex:sub(5, 6), 16) or 0,
  }
end

local function nearest_hl(hex)
  local rgb = hex_to_rgb(hex)
  local best, best_dist = "MiniIconsGrey", math.huge
  for name, p in pairs(hl_palette) do
    local d = (rgb[1] - p[1]) ^ 2 + (rgb[2] - p[2]) ^ 2 + (rgb[3] - p[3]) ^ 2
    if d < best_dist then
      best, best_dist = name, d
    end
  end
  return best
end

return {
  -- Material icon glyph source
  {
    "Allianaab2m/nvim-material-icon-v3",
    lazy = true,
  },

  -- Inject material glyphs into mini.icons
  {
    "echasnovski/mini.icons",
    dependencies = { "Allianaab2m/nvim-material-icon-v3" },
    opts = function(_, opts)
      local material_icons = require("nvim-material-icon").get_icons()

      opts.file = opts.file or {}
      opts.extension = opts.extension or {}

      for key, data in pairs(material_icons) do
        local entry = { glyph = data.icon, hl = nearest_hl(data.color) }
        -- Keys starting with "." are filenames, otherwise extensions
        if key:sub(1, 1) == "." then
          opts.file[key] = entry
        else
          opts.extension[key] = entry
        end
      end

      return opts
    end,
  },

  -- lspkind: VSCode codicons for completion menu
  {
    "onsails/lspkind.nvim",
    lazy = true,
    opts = {
      preset = "codicons",
    },
  },

  -- blink.cmp: use lspkind for kind icons
  {
    "saghen/blink.cmp",
    dependencies = { "onsails/lspkind.nvim" },
    opts = function(_, opts)
      opts.completion = opts.completion or {}
      opts.completion.menu = opts.completion.menu or {}
      opts.completion.menu.draw = opts.completion.menu.draw or {}
      opts.completion.menu.draw.components = opts.completion.menu.draw.components or {}

      opts.completion.menu.draw.components.kind_icon = {
        ellipsis = false,
        text = function(ctx)
          local icon = require("lspkind").symbolic(ctx.kind, { mode = "symbol" })
          return (icon or ctx.kind_icon) .. (ctx.icon_gap or "")
        end,
        highlight = function(ctx)
          return "CmpItemKind" .. ctx.kind
        end,
      }

      return opts
    end,
  },
}
