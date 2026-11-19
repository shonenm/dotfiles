-- dotfiles の floating popup。呼出元 block ごとに一つ作り、同じキーで隠す・再表示する。
-- remote host の session（ctx.server が host）でも server の host 接続から直接作る。
-- host 側に中継 pane を開いて rex-tools に任せると、login sh・Python・rex CLI の起動を待つため遅い。
local M = {}

M.TAG = "dotfiles-popup/"
local TERMINAL = "com.superlogical.terminal"
local SIZES = { editor = { .9, .9 }, pr = { .85, .85 }, prefix = { .65, .55 },
  project = { .7, .7 }, layout = { .7, .6 }, swap = { .8, .4 } }
local COMMANDS = {
  scratch = false, git = { "lazygit" }, pr = { "live-pr" }, editor = { "nvim", "." }, ports = { "quay" },
  database = { "sh", "-c", 'exec pgcli "${DATABASE_URL:-postgresql://postgres:postgres@localhost:5432/postgres}"' },
}
-- rex-tools の画面。popup 内で動くため、host の dotfiles のものを使う。
local VIEWS = { prefix = true, metadata = true, project = true, layout = true, swap = true }
-- Rex は command を login sh で起動し、対話 zsh が PATH に足す mise の shims が無い。
-- mise だけで入れたツール (lazygit / nvim / fzf など) が見つからず pane が即閉じるため足す。
local SHIMS = 'PATH="$HOME/.local/share/mise/shims:$PATH" '

local function bounds(kind)
  local size = SIZES[kind] or { .8, .8 }
  return { (1 - size[1]) / 2, (1 - size[2]) / 2, size[1], size[2] }
end

local function command_for(kind, session, anchor, client)
  if VIEWS[kind] then
    local argv = { "sh", "-c", SHIMS .. 'exec "$HOME/dotfiles/scripts/rex-tools" "$@"', "sh",
      "view", kind, "--session", session, "--block", anchor }
    if client then
      argv[#argv + 1] = "--client"
      argv[#argv + 1] = client
    end
    return argv
  end
  if COMMANDS[kind] then
    return { "sh", "-c", SHIMS .. 'exec "$@"', "sh", unpack(COMMANDS[kind]) }
  end
end

local function cwd_for(call, block, is_local)
  local pwd = call(TERMINAL .. ".pwd", { block_id = block, args = {} }).pwd or ""
  local path = pwd:match("^file://[^/]*(/.*)$")
  if path then
    pwd = path:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
  end
  if pwd == "" then
    local foreground = call(TERMINAL .. ".process", { block_id = block, args = {} }).foreground
    pwd = foreground and foreground.cwd or ""
  end
  -- 手元の pane が container などの cwd を報告した場合に、存在しない cwd で開かない。
  if pwd == "" or (is_local and not rex.exec({ "test", "-d", pwd }).ok) then
    error("呼出元の cwd を取得できません。container は未対応です", 0)
  end
  return pwd
end

function M.open(ctx, kind)
  if COMMANDS[kind] == nil and not VIEWS[kind] then error("不明な popup: " .. kind, 0) end
  local server = rex
  if ctx.server then
    server = rex.server(ctx.server)
    -- host への接続は session に attach しないと session の操作を受け付けない。
    assert(server.call("session.attach", { session_id = ctx.session_id }))
  end
  local function call(method, args)
    args.session_id = ctx.session_id
    local result, err = server.call(method, args)
    if err then error(err, 0) end
    return result
  end

  local blocks, by_id = call("session.list_blocks", {}).blocks, {}
  for _, b in ipairs(blocks) do by_id[b.block_id] = b end
  local caller = by_id[ctx.block_id]
  if not caller then error("呼出元 pane がなくなりました", 0) end
  -- popup から呼んだ場合は、その popup を開いた元の pane を基準にする。
  local anchor = (caller.label or ""):match("^dotfiles%-popup/[^/]*/(.+)$") or ctx.block_id
  local source = by_id[anchor]
  if not source or source.placement ~= "placed" then error("呼出元 pane が表示されていません", 0) end

  local label = M.TAG .. kind .. "/" .. anchor
  for _, b in ipairs(blocks) do
    if b.label == label then
      if kind == "prefix" then
        call("block.close", { block_id = b.block_id })
        call("session.focus_block", { block_id = anchor })
        -- global binding が2回目も拾うため、menu の stdin ではなくここで送る。
        if ctx.block_id == b.block_id then rex.client.queue("pane.send_key", { key = "ctrl+space" }) end
      elseif b.placement == "placed" then
        -- 同じキーは隠すだけ。editor の未保存内容も終了させない。
        call("session.detach_block", { block_id = b.block_id })
        call("session.focus_block", { block_id = anchor })
      else
        call("session.move_block", { block_id = b.block_id, anchor_block_id = anchor })
        call("session.float_block", { block_id = b.block_id, bounds = bounds(kind) })
        call("session.focus_block", { block_id = b.block_id })
      end
      return
    end
  end

  -- remote host の rex-tools は手元の client ID を解決できないため渡さない。
  local options = { cwd = cwd_for(call, anchor, not ctx.server),
    command = command_for(kind, ctx.session_id, anchor, not ctx.server and ctx.client_id or nil) }
  call("session.new_layer", { window_id = source.window_id, bounds = bounds(kind), focus = true,
    layout = { block = { flavor = TERMINAL .. ".shell", label = label, options = options } } })
end

return M
