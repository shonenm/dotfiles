return {
  -- Disable snacks_picker's <leader>gd (Git Diff hunks) to free it for CodeDiff
  { "folke/snacks.nvim", keys = { { "<leader>gd", false } } },
  {
  "esmuellert/codediff.nvim",
  dependencies = { "MunifTanjim/nui.nvim" },
  cmd = { "CodeDiff" },
  keys = {
    { "<leader>gd", "<cmd>CodeDiff<cr>", desc = "CodeDiff Open" },
    { "<leader>gf", "<cmd>CodeDiff history %<cr>", desc = "File History" },
    { "<leader>gF", "<cmd>CodeDiff history<cr>", desc = "Commit History" },
  },
  opts = {
    explorer = {
      view_mode = "tree",
      indent_markers = true,
    },
  },
  config = function(_, opts)
    require("codediff").setup(opts)

    -- Auto-select file on cursor move (j/k updates diff with debounce)
    local keymaps = require("codediff.ui.explorer.keymaps")
    local orig_setup = keymaps.setup
    keymaps.setup = function(explorer)
      orig_setup(explorer)
      local tree = explorer.tree
      local last_node_id = nil
      local debounce_timer = nil
      local debounce_ms = 250
      vim.api.nvim_create_autocmd("CursorMoved", {
        buffer = explorer.bufnr,
        callback = function()
          local node = tree:get_node()
          if not node or not node.data then return end
          if node.data.type == "group" or node.data.type == "directory" then return end
          local node_id = node:get_id()
          if node_id == last_node_id then return end
          last_node_id = node_id
          if debounce_timer then
            debounce_timer:stop()
          end
          debounce_timer = vim.defer_fn(function()
            explorer.on_file_select(node.data)
          end, debounce_ms)
        end,
      })
    end

    -- ヘルプライン用の namespace
    local ns = vim.api.nvim_create_namespace("codediff_help")
    local help_lines = {
      { { "[-]", "Special" }, { " stage  ", "Normal" }, { "[S]", "Special" }, { " all  ", "Normal" }, { "[U]", "Special" }, { " unstage", "Normal" } },
      { { "[X]", "Special" }, { " restore  ", "Normal" }, { "[i]", "Special" }, { " tree/list", "Normal" } },
      { { "[R]", "Special" }, { " refresh  ", "Normal" }, { "[cc]", "Special" }, { " commit", "Normal" } },
    }

    -- 可視範囲の最下部にヘルプを表示
    local function update_help_line(bufnr, winid)
      if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_win_is_valid(winid) then return end
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

      local last_visible = vim.fn.line("w$", winid)
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      local target_line = math.min(last_visible, line_count) - 1

      vim.api.nvim_buf_set_extmark(bufnr, ns, target_line, 0, {
        virt_lines = help_lines,
        virt_lines_above = false,
      })
    end

    local help_initialized = {}

    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = "*",
      callback = function(ev)
        if vim.bo[ev.buf].filetype ~= "codediff-explorer" then return end

        local winid = vim.fn.bufwinid(ev.buf)
        if winid ~= -1 then
          update_help_line(ev.buf, winid)
        end

        -- 初期化は一度だけ
        if not help_initialized[ev.buf] then
          local map_opts = { buffer = ev.buf, noremap = true, silent = true, nowait = true }
          vim.keymap.set("n", "cc", "<cmd>Git commit<cr>", vim.tbl_extend("force", map_opts, { desc = "Git commit" }))
          vim.keymap.set("n", "ca", "<cmd>Git commit --amend<cr>", vim.tbl_extend("force", map_opts, { desc = "Git commit --amend" }))

          -- スクロール・カーソル移動時にヘルプ位置を更新
          vim.api.nvim_create_autocmd({ "CursorMoved", "WinScrolled" }, {
            buffer = ev.buf,
            callback = function()
              local win = vim.fn.bufwinid(ev.buf)
              if win ~= -1 then
                update_help_line(ev.buf, win)
              end
            end,
          })

          help_initialized[ev.buf] = true
        end
      end,
    })
  end,
  },
}
