-- Claude Code CLI <-> Neovim bridge (ACP protocol)
return {
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    cmd = {
      "ClaudeCode",
      "ClaudeCodeSend",
      "ClaudeCodeAdd",
      "ClaudeCodeFocus",
      "ClaudeCodeDiffAccept",
      "ClaudeCodeDiffDeny",
    },
    keys = {
      { "<C-,>", "<cmd>ClaudeCode<cr>", mode = { "n", "t" }, desc = "Toggle Claude Code" },
      { "<leader>Cs", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send to Claude Code" },
      { "<leader>Cb", "<cmd>ClaudeCodeAdd %<cr>", desc = "Add buffer to Claude Code" },
    },
    opts = {
      terminal = {
        split_side = "right",
        split_width_percentage = 0.35,
        provider = "snacks",
      },
    },
  },
}
