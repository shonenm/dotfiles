return {
  {
    "iamcco/markdown-preview.nvim",
    init = function()
      -- Fixed port for SSH port forwarding (ssh -L 8686:localhost:8686)
      vim.g.mkdp_port = "8686"
      vim.g.mkdp_echo_preview_url = 1
      if vim.env.SSH_CONNECTION then
        -- ponytail: headless remote has no xdg-open; empty mkdp_browser still
        -- tries the OS opener and errors. A no-op browserfunc skips the spawn
        -- entirely; the URL is still shown via mkdp_echo_preview_url.
        vim.cmd("function! MkdpNoopBrowser(url) abort\nendfunction")
        vim.g.mkdp_browserfunc = "MkdpNoopBrowser"
      end
    end,
  },
}
