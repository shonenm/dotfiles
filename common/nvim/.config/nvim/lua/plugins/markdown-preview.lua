return {
  {
    "iamcco/markdown-preview.nvim",
    init = function()
      -- Fixed port for SSH port forwarding (ssh -L 8686:localhost:8686)
      vim.g.mkdp_port = "8686"
      vim.g.mkdp_echo_preview_url = 1
      if vim.env.SSH_CONNECTION then
        vim.g.mkdp_browser = ""
      end
    end,
  },
}
