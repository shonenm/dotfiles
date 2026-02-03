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

    -- ヘルプライン用の namespace 作成
    local ns = vim.api.nvim_create_namespace("codediff_help")

    -- バッファ末尾にヘルプを仮想テキストとして追加
    local function add_help_line(bufnr)
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
      local help_text = "[-] stage  [S] all  [U] unstage  [X] restore  [i] tree/list  [R] refresh  [cc] commit"
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      vim.api.nvim_buf_set_extmark(bufnr, ns, line_count - 1, 0, {
        virt_lines = { { { "", "NonText" }, { help_text, "Comment" } } },
        virt_lines_above = false,
      })
    end

    local help_initialized = {}

    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = "*",
      callback = function(ev)
        if vim.bo[ev.buf].filetype ~= "codediff-explorer" then return end

        -- キーマップは一度だけ設定
        if not help_initialized[ev.buf] then
          local map_opts = { buffer = ev.buf, noremap = true, silent = true, nowait = true }
          vim.keymap.set("n", "cc", "<cmd>Git commit<cr>", vim.tbl_extend("force", map_opts, { desc = "Git commit" }))
          vim.keymap.set("n", "ca", "<cmd>Git commit --amend<cr>", vim.tbl_extend("force", map_opts, { desc = "Git commit --amend" }))

          -- BufModifiedSet でツリー更新を検知して再描画
          vim.api.nvim_create_autocmd("BufModifiedSet", {
            buffer = ev.buf,
            callback = function()
              vim.schedule(function()
                if vim.api.nvim_buf_is_valid(ev.buf) then
                  add_help_line(ev.buf)
                end
              end)
            end,
          })

          help_initialized[ev.buf] = true
        end

        -- ヘルプライン表示（毎回更新）
        add_help_line(ev.buf)
      end,
    })
  end,
  },
}
