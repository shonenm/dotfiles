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

    -- Hunk count cache and functions
    local hunk_cache = {
      unstaged = {}, -- { [path] = count }
      staged = {}, -- { [path] = count }
    }

    -- Highlight cache for selected items (avoid repeated nvim_get_hl/nvim_set_hl calls)
    local hl_cache = {}

    local function parse_hunk_counts(output)
      local counts = {}
      local current_file = nil
      for line in output:gmatch("[^\n]+") do
        -- Match "diff --git <prefix>/<path> <prefix>/<path>" with any single-char prefix (a/b or i/w)
        local file = line:match("^diff %-%-git %a/.+ %a/(.+)$")
        if file then
          current_file = file
          counts[current_file] = 0
        elseif current_file and line:match("^@@") then
          counts[current_file] = counts[current_file] + 1
        end
      end
      return counts
    end

    local function fetch_hunk_counts(git_root, callback)
      local pending = 2
      local results = { unstaged = {}, staged = {} }

      local function on_complete()
        pending = pending - 1
        if pending == 0 then
          callback(results)
        end
      end

      -- unstaged
      vim.system({ "git", "diff", "-U0", "--no-color" }, { cwd = git_root, text = true }, function(obj)
        if obj.code == 0 and obj.stdout then
          results.unstaged = parse_hunk_counts(obj.stdout)
        end
        on_complete()
      end)

      -- staged
      vim.system({ "git", "diff", "-U0", "--no-color", "--cached" }, { cwd = git_root, text = true }, function(obj)
        if obj.code == 0 and obj.stdout then
          results.staged = parse_hunk_counts(obj.stdout)
        end
        on_complete()
      end)
    end

    -- Monkey-patch nodes.prepare_node to show hunk counts
    local nodes_mod = require("codediff.ui.explorer.nodes")
    nodes_mod.prepare_node = function(node, max_width, selected_path, selected_group)
      local NuiLine = require("nui.line")
      local line = NuiLine()
      local data = node.data or {}
      local explorer_config = config_mod.options.explorer or {}
      local use_indent_markers = explorer_config.indent_markers ~= false

      local INDENT_MARKERS = {
        edge = "│",
        item = "├",
        last = "└",
        none = " ",
      }

      local function build_indent_markers(indent_state)
        if not indent_state or #indent_state == 0 then
          return ""
        end
        if not use_indent_markers then
          return string.rep("  ", #indent_state)
        end
        local indent_parts = {}
        for i = 1, #indent_state - 1 do
          if indent_state[i] then
            indent_parts[#indent_parts + 1] = INDENT_MARKERS.none .. " "
          else
            indent_parts[#indent_parts + 1] = INDENT_MARKERS.edge .. " "
          end
        end
        if indent_state[#indent_state] then
          indent_parts[#indent_parts + 1] = INDENT_MARKERS.last .. " "
        else
          indent_parts[#indent_parts + 1] = INDENT_MARKERS.item .. " "
        end
        return table.concat(indent_parts)
      end

      if data.type == "group" then
        line:append(" ", "Directory")
        line:append(node.text, "Directory")
      elseif data.type == "directory" then
        local indent = build_indent_markers(data.indent_state)
        local folder_icon, folder_color = nodes_mod.get_folder_icon(node:is_expanded())
        if #indent > 0 then
          line:append(indent, use_indent_markers and "NeoTreeIndentMarker" or "Normal")
        end
        line:append(folder_icon .. " ", folder_color or "Directory")
        line:append(data.name, "Directory")
      else
        local is_selected = data.path and data.path == selected_path and data.group == selected_group

        local selected_bg = nil
        if is_selected then
          local sel_hl = vim.api.nvim_get_hl(0, { name = "CodeDiffExplorerSelected", link = false })
          selected_bg = sel_hl.bg
        end

        local function get_hl(default)
          if not is_selected then
            return default or "Normal"
          end
          local base_hl_name = default or "Normal"
          local combined_name = "CodeDiffExplorerSel_" .. base_hl_name:gsub("[^%w]", "_")

          -- Use cached highlight if available
          if hl_cache[combined_name] then
            return combined_name
          end

          local base_hl = vim.api.nvim_get_hl(0, { name = base_hl_name, link = false })
          local fg = base_hl.fg
          vim.api.nvim_set_hl(0, combined_name, { fg = fg, bg = selected_bg })
          hl_cache[combined_name] = true
          return combined_name
        end

        local view_mode = explorer_config.view_mode or "list"

        local indent
        if view_mode == "tree" and data.indent_state then
          indent = build_indent_markers(data.indent_state)
          if #indent > 0 then
            line:append(indent, get_hl(use_indent_markers and "NeoTreeIndentMarker" or "Normal"))
          end
        else
          indent = string.rep("  ", node:get_depth() - 1)
          line:append(indent, get_hl("Normal"))
        end

        local icon_part = ""
        if data.icon then
          icon_part = data.icon .. " "
          line:append(icon_part, get_hl(data.icon_color))
        end

        local status_symbol = data.status_symbol or ""

        local full_path = data.path or node.text
        local filename = full_path:match("([^/]+)$") or full_path
        local directory = (view_mode == "tree") and "" or full_path:sub(1, -(#filename + 1))

        -- Get hunk count for this file
        local hunk_count = 0
        local group = data.group or "unstaged"
        local cache_key = (group == "staged") and "staged" or "unstaged"
        if hunk_cache[cache_key] and hunk_cache[cache_key][full_path] then
          hunk_count = hunk_cache[cache_key][full_path]
        end
        local hunk_str = (hunk_count > 0) and tostring(hunk_count) or ""

        local used_width = vim.fn.strdisplaywidth(indent) + vim.fn.strdisplaywidth(icon_part)
        -- Reserve space for: hunk_count + space + status + padding
        local hunk_reserve = (hunk_str ~= "") and (vim.fn.strdisplaywidth(hunk_str) + 1) or 0
        local status_reserve = vim.fn.strdisplaywidth(status_symbol) + 3 + hunk_reserve
        local available_for_content = max_width - used_width - status_reserve

        local filename_len = vim.fn.strdisplaywidth(filename)
        local directory_len = vim.fn.strdisplaywidth(directory)
        local space_len = (directory_len > 0) and 1 or 0

        if filename_len + space_len + directory_len > available_for_content then
          local available_for_dir = available_for_content - filename_len - space_len
          if available_for_dir > 3 then
            local ellipsis = "..."
            local chars_to_keep = available_for_dir - vim.fn.strdisplaywidth(ellipsis)
            local byte_pos = 0
            local accumulated_width = 0
            for char in vim.gsplit(directory, "") do
              local char_width = vim.fn.strdisplaywidth(char)
              if accumulated_width + char_width > chars_to_keep then
                break
              end
              accumulated_width = accumulated_width + char_width
              byte_pos = byte_pos + #char
            end
            directory = directory:sub(1, byte_pos) .. ellipsis
          else
            directory = ""
            space_len = 0
          end
        end

        line:append(filename, get_hl("Normal"))
        if #directory > 0 then
          line:append(" ", get_hl("Normal"))
          line:append(directory, get_hl("ExplorerDirectorySmall"))
        end

        local content_len = vim.fn.strdisplaywidth(filename) + space_len + vim.fn.strdisplaywidth(directory)
        local padding_needed = available_for_content - content_len + 2
        if padding_needed > 0 then
          line:append(string.rep(" ", padding_needed), get_hl("Normal"))
        end

        -- Append hunk count before status symbol
        if hunk_str ~= "" then
          line:append(hunk_str, get_hl("Comment"))
          line:append(" ", get_hl("Normal"))
        end

        line:append(status_symbol, get_hl(data.status_color))
        line:append(" ", get_hl("Normal"))
      end

      return line
    end

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

      -- Fetch hunk counts in parallel with status
      local function fetch_and_render()
        if explorer.git_root and not explorer.base_revision then
          -- Only for working tree diff (not revision comparisons)
          fetch_hunk_counts(explorer.git_root, function(counts)
            vim.schedule(function()
              hunk_cache.unstaged = counts.unstaged
              hunk_cache.staged = counts.staged
              -- Re-render to show hunk counts
              if vim.api.nvim_win_is_valid(explorer.winid) then
                explorer.tree:render()
              end
            end)
          end)
        end
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
        fetch_and_render()
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
    local last_help_line = {} -- { [bufnr] = target_line } for skipping redundant updates
    local help_lines = {
      { { "[-]", "Special" }, { " stage  ", "Normal" }, { "[S]", "Special" }, { " all  ", "Normal" }, { "[U]", "Special" }, { " unstage", "Normal" } },
      { { "[X]", "Special" }, { " restore  ", "Normal" }, { "[i]", "Special" }, { " tree/list", "Normal" } },
      { { "[R]", "Special" }, { " refresh  ", "Normal" }, { "[cc]", "Special" }, { " commit", "Normal" } },
    }

    -- 可視範囲の最下部にヘルプを表示
    local function update_help_line(bufnr, winid)
      if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_win_is_valid(winid) then return end

      local last_visible = vim.fn.line("w$", winid)
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      local target_line = math.min(last_visible, line_count) - 1

      -- Skip update if position hasn't changed
      if last_help_line[bufnr] == target_line then
        return
      end
      last_help_line[bufnr] = target_line

      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
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
