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
        -- Reserve space for: hunk_count + space + status_symbol + trailing space
        local hunk_reserve = (hunk_str ~= "") and (vim.fn.strdisplaywidth(hunk_str) + 1) or 0
        local status_reserve = vim.fn.strdisplaywidth(status_symbol) + 1 + hunk_reserve
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
            -- Truncate filename if it still exceeds available space
            if filename_len > available_for_content then
              local ellipsis = "..."
              local ellipsis_width = vim.fn.strdisplaywidth(ellipsis)
              local chars_to_keep = available_for_content - ellipsis_width
              if chars_to_keep > 0 then
                local byte_pos = 0
                local accumulated_width = 0
                for char in vim.gsplit(filename, "") do
                  local char_width = vim.fn.strdisplaywidth(char)
                  if accumulated_width + char_width > chars_to_keep then
                    break
                  end
                  accumulated_width = accumulated_width + char_width
                  byte_pos = byte_pos + #char
                end
                filename = filename:sub(1, byte_pos) .. ellipsis
              else
                filename = ellipsis
              end
            end
          end
        end

        line:append(filename, get_hl("Normal"))
        if #directory > 0 then
          line:append(" ", get_hl("Normal"))
          line:append(directory, get_hl("ExplorerDirectorySmall"))
        end

        local content_len = vim.fn.strdisplaywidth(filename) + space_len + vim.fn.strdisplaywidth(directory)
        local padding_needed = available_for_content - content_len
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

    -- ヘルプライン用の namespace と定義
    local help_ns = vim.api.nvim_create_namespace("codediff_help")
    local explorer_help_lines = {
      { { "[-]", "Special" }, { " stage  ", "Normal" }, { "[S]", "Special" }, { " all  ", "Normal" }, { "[U]", "Special" }, { " unstage", "Normal" } },
      { { "[X]", "Special" }, { " restore  ", "Normal" }, { "[i]", "Special" }, { " tree/list", "Normal" } },
      { { "[R]", "Special" }, { " refresh  ", "Normal" }, { "[cc]", "Special" }, { " commit  ", "Normal" }, { "[q]", "Special" }, { " close", "Normal" } },
    }
    local diff_help_lines = {
      { { "[", "Special" }, { "]c", "Normal" }, { "/", "Special" }, { "[c", "Normal" }, { "]", "Special" }, { " hunk  ", "Normal" }, { "[gs]", "Special" }, { " stage  ", "Normal" }, { "[gr]", "Special" }, { " reset", "Normal" } },
      { { "[do]", "Special" }, { " get  ", "Normal" }, { "[dp]", "Special" }, { " put  ", "Normal" }, { "[Tab]", "Special" }, { " sidebar  ", "Normal" }, { "[q]", "Special" }, { " close", "Normal" } },
    }
    local diff_staged_help_lines = {
      { { "[", "Special" }, { "]c", "Normal" }, { "/", "Special" }, { "[c", "Normal" }, { "]", "Special" }, { " hunk  ", "Normal" }, { "[gu]", "Special" }, { " unstage  ", "Normal" }, { "[gr]", "Special" }, { " reset", "Normal" } },
      { { "[do]", "Special" }, { " get  ", "Normal" }, { "[dp]", "Special" }, { " put  ", "Normal" }, { "[Tab]", "Special" }, { " sidebar  ", "Normal" }, { "[q]", "Special" }, { " close", "Normal" } },
    }
    local conflict_help_lines = {
      { { "[co]", "Special" }, { " ours  ", "Normal" }, { "[ct]", "Special" }, { " theirs  ", "Normal" }, { "[cb]", "Special" }, { " both  ", "Normal" }, { "[c0]", "Special" }, { " none", "Normal" } },
      { { "[", "Special" }, { "]x", "Normal" }, { "/", "Special" }, { "[x", "Normal" }, { "]", "Special" }, { " conflict  ", "Normal" }, { "[Tab]", "Special" }, { " sidebar  ", "Normal" }, { "[q]", "Special" }, { " close", "Normal" } },
    }

    -- view.updateをラップしてeventignoreを設定
    -- オリジナルのview.updateを使いつつ、BufEnter/WinEnterのみを一時的に抑制
    local view_mod = require("codediff.ui.view")
    local orig_view_update = view_mod.update
    view_mod.update = function(tabpage, session_config, auto_scroll)
      local eventignore_save = vim.o.eventignore
      vim.o.eventignore = "BufEnter,WinEnter"

      local ok, result = pcall(orig_view_update, tabpage, session_config, auto_scroll)

      vim.o.eventignore = eventignore_save

      if not ok then error(result) end
      return result
    end

    -- Phase 2: auto_refresh throttle adjustment (200ms → 400ms)
    -- Wrap enable() to use custom throttle timer
    local auto_refresh_mod = require("codediff.ui.auto_refresh")
    local CUSTOM_THROTTLE_MS = 400 -- Increased from 200ms
    local custom_timers = {} -- Track our custom timers

    local orig_enable = auto_refresh_mod.enable
    auto_refresh_mod.enable = function(bufnr)
      -- Call original to set up autocmds
      orig_enable(bufnr)

      -- Override the autocmds with our custom throttle
      local buf_augroup = "codediff_auto_refresh_" .. bufnr
      pcall(vim.api.nvim_del_augroup_by_name, buf_augroup)

      local group = vim.api.nvim_create_augroup(buf_augroup, { clear = true })

      local function trigger_with_custom_throttle()
        if custom_timers[bufnr] then
          vim.fn.timer_stop(custom_timers[bufnr])
        end
        custom_timers[bufnr] = vim.fn.timer_start(CUSTOM_THROTTLE_MS, function()
          custom_timers[bufnr] = nil
          auto_refresh_mod.trigger(bufnr)
        end)
      end

      vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
        group = group,
        buffer = bufnr,
        callback = trigger_with_custom_throttle,
      })

      vim.api.nvim_create_autocmd({ "FileChangedShellPost", "FocusGained" }, {
        group = group,
        buffer = bufnr,
        callback = trigger_with_custom_throttle,
      })

      vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = group,
        buffer = bufnr,
        callback = function()
          if custom_timers[bufnr] then
            vim.fn.timer_stop(custom_timers[bufnr])
            custom_timers[bufnr] = nil
          end
          auto_refresh_mod.disable(bufnr)
        end,
      })
    end

    -- Phase 2: Diff result cache (skip recomputation for unchanged files)
    local diff_cache = {}
    local MAX_CACHE_SIZE = 20
    local cache_keys = {} -- Track insertion order for LRU eviction

    local function make_cache_key(original_path, modified_path, original_rev, modified_rev)
      return string.format("%s:%s:%s:%s",
        original_path or "",
        modified_path or "",
        original_rev or "WORKING",
        modified_rev or "WORKING")
    end

    local function get_cached_diff(key, original_tick, modified_tick)
      local entry = diff_cache[key]
      if entry and entry.original_tick == original_tick and entry.modified_tick == modified_tick then
        return entry.diff_result
      end
      return nil
    end

    local function set_cached_diff(key, diff_result, original_tick, modified_tick)
      -- LRU eviction
      if #cache_keys >= MAX_CACHE_SIZE then
        local oldest_key = table.remove(cache_keys, 1)
        diff_cache[oldest_key] = nil
      end
      -- Remove existing key if present (for reordering)
      for i, k in ipairs(cache_keys) do
        if k == key then
          table.remove(cache_keys, i)
          break
        end
      end
      table.insert(cache_keys, key)
      diff_cache[key] = {
        diff_result = diff_result,
        original_tick = original_tick,
        modified_tick = modified_tick,
      }
    end

    -- Wrap render.compute_and_render to use cached diff when available
    local render_mod = require("codediff.ui.view.render")
    local core_mod = require("codediff.ui.core")
    local semantic_mod = require("codediff.ui.semantic_tokens")
    local orig_compute_and_render = render_mod.compute_and_render

    render_mod.compute_and_render = function(original_buf, modified_buf, original_lines, modified_lines, original_is_virtual, modified_is_virtual, original_win, modified_win, auto_scroll_to_first_hunk)
      -- Try to find cache key from buffer names
      local original_name = vim.api.nvim_buf_get_name(original_buf)
      local modified_name = vim.api.nvim_buf_get_name(modified_buf)

      -- Extract path and revision from virtual file names (format: codediff://<git_root>//<rev>//<path>)
      local function parse_virtual_name(name)
        local rev, path = name:match("codediff://[^/]+//([^/]+)//(.+)$")
        if rev and path then
          return path, rev
        end
        -- For real files, use the path as-is
        return name, "WORKING"
      end

      local original_path, original_rev = parse_virtual_name(original_name)
      local modified_path, modified_rev = parse_virtual_name(modified_name)
      local key = make_cache_key(original_path, modified_path, original_rev, modified_rev)

      local original_tick = vim.api.nvim_buf_get_changedtick(original_buf)
      local modified_tick = vim.api.nvim_buf_get_changedtick(modified_buf)

      -- Check cache
      local cached_diff = get_cached_diff(key, original_tick, modified_tick)
      if cached_diff then
        -- Cache hit: skip diff computation, just re-render with cached result
        core_mod.render_diff(original_buf, modified_buf, original_lines, modified_lines, cached_diff)

        -- Apply semantic tokens for virtual buffers
        if original_is_virtual then
          semantic_mod.apply_semantic_tokens(original_buf, modified_buf)
        end
        if modified_is_virtual then
          semantic_mod.apply_semantic_tokens(modified_buf, original_buf)
        end

        -- Setup scrollbind (copied from original)
        if original_win and modified_win and vim.api.nvim_win_is_valid(original_win) and vim.api.nvim_win_is_valid(modified_win) then
          local saved_cursor = nil
          if not auto_scroll_to_first_hunk then
            saved_cursor = vim.api.nvim_win_get_cursor(modified_win)
          end

          vim.wo[original_win].scrollbind = false
          vim.wo[modified_win].scrollbind = false
          vim.api.nvim_win_set_cursor(original_win, { 1, 0 })
          vim.api.nvim_win_set_cursor(modified_win, { 1, 0 })
          vim.wo[original_win].scrollbind = true
          vim.wo[modified_win].scrollbind = true
          vim.wo[original_win].wrap = false
          vim.wo[modified_win].wrap = false

          if auto_scroll_to_first_hunk and #cached_diff.changes > 0 then
            local first_change = cached_diff.changes[1]
            local target_line = first_change.original.start_line
            pcall(vim.api.nvim_win_set_cursor, original_win, { target_line, 0 })
            pcall(vim.api.nvim_win_set_cursor, modified_win, { target_line, 0 })
            if vim.api.nvim_win_is_valid(modified_win) then
              vim.api.nvim_set_current_win(modified_win)
              vim.cmd("normal! zz")
            end
          elseif saved_cursor then
            pcall(vim.api.nvim_win_set_cursor, modified_win, saved_cursor)
            pcall(vim.api.nvim_win_set_cursor, original_win, { saved_cursor[1], 0 })
          end
        end

        return cached_diff
      end

      -- Cache miss: compute diff normally
      local lines_diff = orig_compute_and_render(original_buf, modified_buf, original_lines, modified_lines, original_is_virtual, modified_is_virtual, original_win, modified_win, auto_scroll_to_first_hunk)

      -- Store in cache
      if lines_diff then
        set_cached_diff(key, lines_diff, original_tick, modified_tick)
      end

      return lines_diff
    end

    -- Stage/Reset後にdiffビューを自動更新する関数
    -- is_stage: true=gs(stage), false=gr(reset)
    local function refresh_diff_view(is_stage)
      vim.defer_fn(function()
        local session_mod = require("codediff.ui.lifecycle.session")
        local tabpage = vim.api.nvim_get_current_tabpage()
        local active_diffs = session_mod.get_active_diffs()
        local session = active_diffs[tabpage]
        if not session then return end

        local explorer = session.explorer
        if not explorer then return end
        if not session.original_path or not session.modified_path then return end

        -- diffキャッシュの該当エントリを無効化
        local file_path = explorer.current_file_path
        if file_path then
          local keys_to_remove = {}
          for _, key in ipairs(cache_keys) do
            if key:find(file_path, 1, true) then
              keys_to_remove[#keys_to_remove + 1] = key
            end
          end
          for _, key in ipairs(keys_to_remove) do
            diff_cache[key] = nil
            for i, k in ipairs(cache_keys) do
              if k == key then
                table.remove(cache_keys, i)
                break
              end
            end
          end
        end

        -- original_revision を決定
        -- gs: ステージ後は必ず ":0" と比較（staged content が存在する）
        -- gr: 参照側は変わらないのでセッションの値をそのまま使用
        local original_revision = session.original_revision
        if is_stage and session.modified_revision == nil then
          -- unstaged view (modified = working tree) の場合のみ ":0" に切替
          original_revision = ":0"
        end

        local session_config = {
          mode = "explorer",
          git_root = session.git_root,
          original_path = session.original_path,
          modified_path = session.modified_path,
          original_revision = original_revision,
          modified_revision = session.modified_revision,
        }
        view_mod.update(tabpage, session_config, false)

        -- explorerツリーも明示的に更新（fs_eventより速い）
        if explorer.winid and vim.api.nvim_win_is_valid(explorer.winid) then
          refresh_mod.refresh(explorer)
        end
      end, 150)
    end

    -- Auto-select file on cursor move (j/k updates diff with debounce)
    local keymaps = require("codediff.ui.explorer.keymaps")
    local orig_setup = keymaps.setup
    keymaps.setup = function(explorer)
      orig_setup(explorer)
      local tree = explorer.tree

      -- on_file_selectをラップしてフォーカス復元 + 大ファイル警告
      local orig_on_file_select = explorer.on_file_select
      local large_file_warned = {} -- Track warned files to avoid repeated warnings
      explorer.on_file_select = function(file_data)
        -- Large file warning (>1500 lines)
        if file_data and file_data.path and not large_file_warned[file_data.path] then
          local full_path = explorer.git_root and (explorer.git_root .. "/" .. file_data.path) or file_data.path
          local ok, stat = pcall(vim.uv.fs_stat, full_path)
          if ok and stat and stat.size > 75000 then -- ~1500 lines assuming 50 bytes/line
            vim.notify("Large file: diff may be slow", vim.log.levels.WARN, { title = "CodeDiff" })
            large_file_warned[file_data.path] = true
          end
        end

        local saved_win = explorer.winid

        -- CodeDiffVirtualFileLoadedでフォーカス復元（非同期パス用）
        local group = vim.api.nvim_create_augroup("CodeDiffFocusRestore", { clear = true })
        vim.api.nvim_create_autocmd("User", {
          group = group,
          pattern = "CodeDiffVirtualFileLoaded",
          once = true,
          callback = function()
            vim.schedule(function()
              if vim.api.nvim_win_is_valid(saved_win) then
                vim.api.nvim_set_current_win(saved_win)
              end
            end)
          end,
        })

        -- 同期パス用フォールバック
        vim.defer_fn(function()
          pcall(vim.api.nvim_del_augroup_by_id, group)
          if vim.api.nvim_win_is_valid(saved_win) and vim.api.nvim_get_current_win() ~= saved_win then
            vim.api.nvim_set_current_win(saved_win)
          end
        end, 200)

        orig_on_file_select(file_data)
      end

      -- ヘルプ表示関数（このexplorerに特化）
      local function update_help_line()
        local bufnr = explorer.bufnr
        local winid = explorer.winid
        if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_win_is_valid(winid) then return end

        local win_height = vim.api.nvim_win_get_height(winid)
        local line_count = vim.api.nvim_buf_line_count(bufnr)
        local first_visible = vim.fn.line("w0", winid)
        local help_height = #explorer_help_lines -- both help tables have similar height
        -- ウィンドウ下部にヘルプを固定（最低限の領域確保）
        local max_target = first_visible + win_height - help_height - 2
        local target_line = math.min(max_target, line_count - 1)
        if target_line < 0 then target_line = 0 end

        -- diffview にフォーカスがあるか判定 + コンフリクト状態チェック
        local in_diff = false
        local in_conflict = false
        local lifecycle_mod = require("codediff.ui.lifecycle")
        local tabpage = vim.api.nvim_get_current_tabpage()
        local original_bufnr, modified_bufnr = lifecycle_mod.get_buffers(tabpage)
        if original_bufnr and modified_bufnr then
          local cur_buf = vim.api.nvim_get_current_buf()
          in_diff = cur_buf == original_bufnr or cur_buf == modified_bufnr
          -- コンフリクト状態をチェック（git-conflict.nvim）
          -- modified_bufnr を使用（実ファイルにコンフリクトがある）
          if in_diff then
            local ok, git_conflict = pcall(require, "git-conflict")
            if ok and git_conflict.conflict_count then
              local count = git_conflict.conflict_count(modified_bufnr)
              in_conflict = count and count > 0
            end
          end
        end
        local help_lines
        if in_conflict then
          help_lines = conflict_help_lines
        elseif in_diff then
          local in_staged = false
          local session_check = require("codediff.ui.lifecycle.session").get_active_diffs()[tabpage]
          if session_check and session_check.modified_revision == ":0" then
            in_staged = true
          end
          help_lines = in_staged and diff_staged_help_lines or diff_help_lines
        else
          help_lines = explorer_help_lines
        end

        vim.api.nvim_buf_clear_namespace(bufnr, help_ns, 0, -1)
        vim.api.nvim_buf_set_extmark(bufnr, help_ns, target_line, 0, {
          virt_lines = help_lines,
          virt_lines_above = false,
        })
      end

      -- tree.render をラップして、render 後に必ずヘルプを表示
      local orig_render = tree.render
      tree.render = function(self, ...)
        local result = orig_render(self, ...)
        vim.schedule(update_help_line)
        return result
      end

      -- WinEnter/BufEnter でヘルプ内容を切り替え（diffview <-> explorer）
      -- BufEnterも併用することでより確実にヘルプを更新
      vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
        callback = function()
          if not vim.api.nvim_buf_is_valid(explorer.bufnr) then return end
          if not vim.api.nvim_win_is_valid(explorer.winid) then return end
          -- explorerが属するタブページでのみ処理
          local current_tabpage = vim.api.nvim_get_current_tabpage()
          local explorer_tabpage = vim.api.nvim_win_get_tabpage(explorer.winid)
          if current_tabpage ~= explorer_tabpage then return end
          vim.schedule(update_help_line)
        end,
      })

      -- スクロール時にヘルプ位置を更新
      vim.api.nvim_create_autocmd("WinScrolled", {
        buffer = explorer.bufnr,
        callback = function()
          vim.schedule(update_help_line)
        end,
      })

      -- キーマップ追加
      local map_opts = { buffer = explorer.bufnr, noremap = true, silent = true, nowait = true }
      vim.keymap.set("n", "q", function()
        vim.cmd("tabclose")
      end, vim.tbl_extend("force", map_opts, { desc = "Close CodeDiff" }))
      vim.keymap.set("n", "cc", "<cmd>Git commit<cr>", vim.tbl_extend("force", map_opts, { desc = "Git commit" }))
      vim.keymap.set("n", "ca", "<cmd>Git commit --amend<cr>", vim.tbl_extend("force", map_opts, { desc = "Git commit --amend" }))
      local last_node_id = nil
      local debounce_timer = nil
      local debounce_ms = 750 -- Increased from 400ms; use Enter for immediate refresh
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
          vim.schedule(function()
            is_toggling = false
            update_help_line() -- explorer用ヘルプに更新
          end)
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
          vim.schedule(update_help_line) -- diff用ヘルプに切り替え
        end
      end, vim.tbl_extend("force", map_opts, { desc = "Expand directory or focus diff view" }))
      vim.keymap.set("n", "<Tab>", function()
        vim.cmd("2wincmd l")
        vim.schedule(update_help_line)
      end, vim.tbl_extend("force", map_opts, { desc = "Focus diff view" }))
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
          -- ファイルノードの場合は即座に選択（debounceをスキップ）
          if node and node.data then
            if debounce_timer then
              debounce_timer:stop()
              debounce_timer = nil
            end
            last_node_id = node:get_id() -- Prevent duplicate trigger from CursorMoved
            explorer.on_file_select(node.data)
          end
        end
      end, vim.tbl_extend("force", map_opts, { desc = "Toggle directory or select file" }))
    end

    -- staged viewでカーソル位置のhunkをunstageする関数
    local function unstage_hunk()
      local ok, session_mod = pcall(require, "codediff.ui.lifecycle.session")
      if not ok then return end
      local active_diffs = session_mod.get_active_diffs()
      local session = active_diffs[vim.api.nvim_get_current_tabpage()]
      if not session then return end

      if session.modified_revision ~= ":0" then
        vim.notify("Not in staged diff view", vim.log.levels.WARN)
        return
      end

      local git_root = session.git_root
      local explorer = session.explorer
      local file_path = explorer and explorer.current_file_path
      if not file_path then return end

      local cur_buf = vim.api.nvim_get_current_buf()
      local is_modified = cur_buf == session.modified_bufnr
      local is_original = cur_buf == session.original_bufnr
      if not is_modified and not is_original then return end

      local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

      vim.system(
        { "git", "diff", "--cached", "-U0", "--no-color", "--", file_path },
        { cwd = git_root, text = true },
        function(obj)
          if obj.code ~= 0 or not obj.stdout or obj.stdout == "" then
            vim.schedule(function() vim.notify("No staged diff", vim.log.levels.WARN) end)
            return
          end

          local lines = vim.split(obj.stdout, "\n")
          local header_lines, hunks, current_hunk = {}, {}, nil

          for _, line in ipairs(lines) do
            local os_str, oc, ns, nc = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
            if os_str then
              if current_hunk then hunks[#hunks + 1] = current_hunk end
              current_hunk = {
                header = line, body = {},
                old_start = tonumber(os_str), old_count = tonumber(oc ~= "" and oc or "1"),
                new_start = tonumber(ns), new_count = tonumber(nc ~= "" and nc or "1"),
              }
            elseif current_hunk then
              current_hunk.body[#current_hunk.body + 1] = line
            else
              header_lines[#header_lines + 1] = line
            end
          end
          if current_hunk then hunks[#hunks + 1] = current_hunk end

          local matched = nil
          for _, h in ipairs(hunks) do
            local s = is_modified and h.new_start or h.old_start
            local c = is_modified and h.new_count or h.old_count
            if c == 0 then
              if cursor_line == s or cursor_line == s + 1 then matched = h; break end
            elseif cursor_line >= s and cursor_line <= s + c - 1 then
              matched = h; break
            end
          end

          if not matched then
            vim.schedule(function() vim.notify("No hunk at cursor", vim.log.levels.INFO) end)
            return
          end

          local patch = table.concat(header_lines, "\n") .. "\n" .. matched.header .. "\n" .. table.concat(matched.body, "\n")
          if not patch:match("\n$") then patch = patch .. "\n" end

          vim.system(
            { "git", "apply", "--reverse", "--cached", "--unidiff-zero", "-" },
            { cwd = git_root, text = true, stdin = patch },
            function(apply_obj)
              vim.schedule(function()
                if apply_obj.code ~= 0 then
                  vim.notify("Unstage failed: " .. (apply_obj.stderr or ""), vim.log.levels.ERROR)
                  return
                end
                refresh_diff_view(false)
              end)
            end
          )
        end
      )
    end

    -- diffviewバッファ用のキーマップ
    local diffview_initialized = {}
    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = "*",
      callback = function(ev)
        if diffview_initialized[ev.buf] then return end

        -- セッション情報からdiffviewバッファかどうか判定
        local ok, session_mod = pcall(require, "codediff.ui.lifecycle.session")
        if not ok then return end
        local active_diffs = session_mod.get_active_diffs()
        local session = active_diffs[vim.api.nvim_get_current_tabpage()]
        if not session then return end
        if ev.buf ~= session.original_bufnr and ev.buf ~= session.modified_bufnr then return end

        local map_opts = { buffer = ev.buf, noremap = true, silent = true, nowait = true }
        vim.keymap.set({ "n", "v" }, "gs", function()
          vim.cmd("Gitsigns stage_hunk")
          refresh_diff_view(true)
        end, vim.tbl_extend("force", map_opts, { desc = "Stage hunk" }))
        vim.keymap.set({ "n", "v" }, "gr", function()
          vim.cmd("Gitsigns reset_hunk")
          refresh_diff_view(false)
        end, vim.tbl_extend("force", map_opts, { desc = "Reset hunk" }))
        vim.keymap.set({ "n", "v" }, "gu", function()
          unstage_hunk()
        end, vim.tbl_extend("force", map_opts, { desc = "Unstage hunk" }))
        vim.keymap.set("n", "<Tab>", function()
          local ok2, session_mod2 = pcall(require, "codediff.ui.lifecycle.session")
          if not ok2 then return end
          local active_diffs2 = session_mod2.get_active_diffs()
          local session2 = active_diffs2[vim.api.nvim_get_current_tabpage()]
          if session2 and session2.explorer and session2.explorer.winid and vim.api.nvim_win_is_valid(session2.explorer.winid) then
            vim.api.nvim_set_current_win(session2.explorer.winid)
          end
        end, vim.tbl_extend("force", map_opts, { desc = "Focus sidebar" }))

        diffview_initialized[ev.buf] = true
      end,
    })
  end,
  },
}
