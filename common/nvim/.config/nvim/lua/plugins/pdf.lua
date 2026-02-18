local function preview_pdf(pdf_path)
  if vim.fn.executable("fancy-cat") == 1 and vim.env.TMUX then
    -- tmux detach trick: 一時的に tmux を離脱して fancy-cat を直接実行
    local session = vim.fn.trim(vim.fn.system("tmux display-message -p '#S'"))
    local cmd = string.format(
      "fancy-cat %s; exec tmux attach-session -t %s",
      vim.fn.shellescape(pdf_path),
      vim.fn.shellescape(session)
    )
    vim.fn.system({ "tmux", "detach-client", "-E", cmd })
  elseif vim.fn.executable("fancy-cat") == 1 then
    -- tmux 外: fancy-cat を直接起動
    vim.fn.jobstart({ "fancy-cat", pdf_path }, { detach = true })
  elseif vim.fn.has("mac") == 1 then
    vim.fn.system({ "open", pdf_path })
  else
    vim.fn.system({ "xdg-open", pdf_path })
  end
end

return {
  {
    "chomosuke/typst-preview.nvim",
    keys = {
      { "<leader>cp", false },
    },
  },

  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "typst",
        callback = function(ev)
          vim.keymap.set("n", "<leader>cp", function()
            local file = vim.fn.expand("%:p")
            local pdf = file:gsub("%.typ$", ".pdf")
            if vim.fn.filereadable(pdf) == 1 then
              preview_pdf(pdf)
            else
              vim.notify("PDF not found: " .. pdf .. "\nRun typst compile first", vim.log.levels.WARN)
            end
          end, { buffer = ev.buf, desc = "Typst Preview (fancy-cat)" })
        end,
      })
      return opts
    end,
  },
}
