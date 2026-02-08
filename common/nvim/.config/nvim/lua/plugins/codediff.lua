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

    -- Runtime monkey-patch: Fix collapsed state key to use dir_path for unique identification
    -- This avoids modifying source files which would block Lazy.nvim updates
    -- See: docs/patches/codediff-directory-collapse.md
    local refresh_mod = require("codediff.ui.explorer.refresh")
    local config_mod = require("codediff.config")

    -- Fixed collect_collapsed_state (uses dir_path for unique key)
    local function collect_collapsed_state(tree)
      local collapsed = {}
      local function collect_from_node(node)
        if not node.data then return end
        local node_type = node.data.type
        if node_type == "group" or node_type == "directory" then
          local key = node.data.dir_path or node.data.path or node.data.name
          if key and not node:is_expanded() then
            collapsed[key] = true
          end
          if node:has_children() then
            for _, child_id in ipairs(node:get_child_ids()) do
              local child = tree:get_node(child_id)
              if child then collect_from_node(child) end
            end
          end
        end
      end
      for _, node in ipairs(tree:get_nodes()) do
        collect_from_node(node)
      end
      return collapsed
    end

    -- Fixed restore_collapsed_state (uses dir_path for unique key)
    local function restore_collapsed_state(tree, collapsed, root_nodes)
      local function restore_node(node)
        if not node.data then return end
        local node_type = node.data.type
        if node_type == "group" or node_type == "directory" then
          local key = node.data.dir_path or node.data.path or node.data.name
          if key and collapsed[key] then
            node:collapse()
          end
          if node:has_children() then
            for _, child_id in ipairs(node:get_child_ids()) do
              local child = tree:get_node(child_id)
              if child then restore_node(child) end
            end
          end
        end
      end
      for _, node in ipairs(root_nodes) do
        restore_node(node)
      end
    end

    -- Replace M.refresh with fixed version (captures fixed local functions)
    refresh_mod.refresh = function(explorer)
      local git = require("codediff.core.git")

      if explorer.is_hidden then return end
      if not vim.api.nvim_win_is_valid(explorer.winid) then return end

      local current_node = explorer.tree:get_node()
      local current_path = current_node and current_node.data and current_node.data.path
      local collapsed_state = collect_collapsed_state(explorer.tree)

      local function process_result(err, status_result)
        vim.schedule(function()
          if err then
            vim.notify("Failed to refresh: " .. err, vim.log.levels.ERROR)
            return
          end

          local tree_module = require("codediff.ui.explorer.tree")
          local root_nodes = tree_module.create_tree_data(status_result, explorer.git_root, explorer.base_revision, not explorer.git_root)

          for _, node in ipairs(root_nodes) do
            node:expand()
          end

          explorer.tree:set_nodes(root_nodes)

          local explorer_config = config_mod.options.explorer or {}
          if explorer_config.view_mode == "tree" then
            local function expand_all_dirs(parent_node)
              if not parent_node:has_children() then return end
              for _, child_id in ipairs(parent_node:get_child_ids()) do
                local child = explorer.tree:get_node(child_id)
                if child and child.data and child.data.type == "directory" then
                  child:expand()
                  expand_all_dirs(child)
                end
              end
            end
            for _, node in ipairs(root_nodes) do
              expand_all_dirs(node)
            end
          end

          restore_collapsed_state(explorer.tree, collapsed_state, root_nodes)
          explorer.tree:render()
          explorer.status_result = status_result

          if current_path then
            local nodes = explorer.tree:get_nodes()
            for _, node in ipairs(nodes) do
              if node.data and node.data.path == current_path then
                explorer.tree:set_node(node:get_id())
                break
              end
            end
          end
        end)
      end

      if not explorer.git_root then
        local dir_mod = require("codediff.core.dir")
        local diff = dir_mod.diff_directories(explorer.dir1, explorer.dir2)
        process_result(nil, diff.status_result)
      elseif explorer.base_revision and explorer.target_revision and explorer.target_revision ~= "WORKING" then
        git.get_diff_revisions(explorer.base_revision, explorer.target_revision, explorer.git_root, process_result)
      elseif explorer.base_revision then
        git.get_diff_revision(explorer.base_revision, explorer.git_root, process_result)
      else
        git.get_status(explorer.git_root, process_result)
      end
    end

    -- Auto-select file on cursor move (j/k updates diff with debounce)
    local keymaps = require("codediff.ui.explorer.keymaps")
    local orig_setup = keymaps.setup
    keymaps.setup = function(explorer)
      orig_setup(explorer)
      local tree = explorer.tree
      local last_node_id = nil
      local debounce_timer = nil
      local debounce_ms = 400
      local is_toggling = false
      vim.api.nvim_create_autocmd("CursorMoved", {
        buffer = explorer.bufnr,
        callback = function()
          if is_toggling then return end
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
      local map_opts = { buffer = explorer.bufnr, noremap = true, silent = true, nowait = true }
      vim.keymap.set("n", "h", function()
        local node = tree:get_node()
        if node and node:has_children() and node:is_expanded() then
          if debounce_timer then
            debounce_timer:stop()
            debounce_timer = nil
          end
          is_toggling = true
          node:collapse()
          tree:render()
          vim.schedule(function() is_toggling = false end)
        end
      end, vim.tbl_extend("force", map_opts, { desc = "Collapse directory" }))
      vim.keymap.set("n", "l", function()
        local node = tree:get_node()
        if node and node:has_children() and not node:is_expanded() then
          if debounce_timer then
            debounce_timer:stop()
            debounce_timer = nil
          end
          is_toggling = true
          node:expand()
          tree:render()
          vim.schedule(function() is_toggling = false end)
        else
          vim.cmd("2wincmd l")
        end
      end, vim.tbl_extend("force", map_opts, { desc = "Expand directory or focus diff view" }))
      vim.keymap.set("n", "<CR>", function()
        local node = tree:get_node()
        if node and node:has_children() then
          if debounce_timer then
            debounce_timer:stop()
            debounce_timer = nil
          end
          is_toggling = true
          if node:is_expanded() then
            node:collapse()
          else
            node:expand()
          end
          tree:render()
          vim.schedule(function() is_toggling = false end)
        else
          -- ファイルノードの場合は通常の選択動作
          if node and node.data then
            explorer.on_file_select(node.data)
          end
        end
      end, vim.tbl_extend("force", map_opts, { desc = "Toggle directory or select file" }))
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
