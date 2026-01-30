return {
  "vuki656/package-info.nvim",
  dependencies = { "MunifTanjim/nui.nvim" },
  ft = "json",
  keys = {
    { "<leader>np", function() require("package-info").toggle() end, desc = "Toggle Package Versions" },
    { "<leader>nu", function() require("package-info").update() end, desc = "Update Package" },
    { "<leader>nd", function() require("package-info").delete() end, desc = "Delete Package" },
    { "<leader>ni", function() require("package-info").install() end, desc = "Install Package" },
    { "<leader>nc", function() require("package-info").change_version() end, desc = "Change Version" },
  },
  opts = {
    package_manager = "pnpm",
    autostart = true,
    hide_up_to_date = false,
    hide_unstable_versions = true,
  },
}
