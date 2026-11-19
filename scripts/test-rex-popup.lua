-- popup.lua の unit test。rex を mock し、luajit で実行する（test-rex-tools.py から呼ぶ）。
local dir = arg[0]:match("^(.*)/") or "."
local calls, queued, attached

local function server(label, blocks, state)
  return {
    call = function(method, args)
      table.insert(calls, { label = label, method = method, args = args })
      if method == "session.attach" then attached = args.session_id return {} end
      if method == "session.list_blocks" then return { blocks = blocks } end
      if method:match("%.pwd$") then return state.pwd and { pwd = state.pwd } or {} end
      if method:match("%.process$") then return { foreground = state.cwd and { cwd = state.cwd } or nil } end
      return {}
    end,
  }
end

local function setup(blocks, state)
  calls, queued, attached = {}, {}, nil
  state = state or {}
  rex = setmetatable({
    server = function(label) return server(label, blocks, state) end,
    exec = function(argv) return { ok = state.is_dir ~= false } end,
    client = { queue = function(name, args) table.insert(queued, { name, args }) end },
  }, { __index = server("local", blocks, state) })
  rex.call = server("local", blocks, state).call
  package.loaded.popup = nil
  return dofile(dir .. "/../common/rex/.config/rex/popup.lua")
end

local function methods(skip)
  local out = {}
  for _, c in ipairs(calls) do
    if not (skip and skip[c.method]) then out[#out + 1] = c.method end
  end
  return table.concat(out, ",")
end

local function eq(got, want, name)
  if got ~= want then error(name .. ": got " .. tostring(got) .. ", want " .. tostring(want), 2) end
end

local skip = { ["session.list_blocks"] = true, ["session.attach"] = true }
local anchor = { block_id = "a", label = "shell", placement = "placed", window_id = "w" }

-- 新規作成は呼出元 window に、cwd と mise shims 付き command・kind のサイズで作る。
local popup = setup({ anchor }, { pwd = "file://localhost/tmp/a%20b" })
popup.open({ session_id = "s", block_id = "a", client_id = "c" }, "git")
local layer = calls[#calls]
eq(layer.method, "session.new_layer", "new layer")
eq(layer.args.window_id, "w", "window")
eq(layer.args.bounds[3], .8, "width")
local options = layer.args.layout.block.options
eq(options.cwd, "/tmp/a b", "cwd")
eq(options.command[3], 'PATH="$HOME/.local/share/mise/shims:$PATH" exec "$@"', "shims")
eq(options.command[5], "lazygit", "command")
eq(layer.args.layout.block.label, "dotfiles-popup/git/a", "label")

-- 画面は host の rex-tools を使い、手元の client ID は local のときだけ渡す。
popup = setup({ anchor }, { cwd = "/tmp" })
popup.open({ session_id = "s", block_id = "a", client_id = "c" }, "metadata")
local view = calls[#calls].args.layout.block.options.command
eq(view[#view - 1] .. " " .. view[#view], "--client c", "local client")
eq(calls[#calls].args.bounds[3], .8, "default size")

-- remote host は host 接続で attach してから作り、client ID を渡さない。
popup = setup({ anchor }, { cwd = "/home/u" })
popup.open({ server = "host", session_id = "s", block_id = "a", client_id = "c" }, "prefix")
eq(attached, "s", "attach")
eq(calls[#calls].label, "host", "remote server")
view = calls[#calls].args.layout.block.options.command
eq(view[#view], "a", "remote no client")
eq(calls[#calls].args.bounds[3], .65, "prefix size")

-- 同じ popup が表示中なら隠すだけで、process は終了させない。
local shown = { block_id = "p", label = "dotfiles-popup/scratch/a", placement = "placed" }
popup = setup({ anchor, shown })
popup.open({ session_id = "s", block_id = "a" }, "scratch")
eq(methods(skip), "session.detach_block,session.focus_block", "toggle")

-- popup から呼んでも元の pane を基準にする。隠れた popup は同じ block を再表示する。
local hidden = { block_id = "p", label = "dotfiles-popup/scratch/a", placement = "detached" }
local other = { block_id = "q", label = "dotfiles-popup/git/a", placement = "placed" }
popup = setup({ anchor, hidden, other })
popup.open({ session_id = "s", block_id = "q" }, "scratch")
eq(methods(skip), "session.move_block,session.float_block,session.focus_block", "reopen")
eq(calls[#calls].args.block_id, "p", "reopen block")

-- prefix menu の中で再度 prefix を押すと menu を閉じ、元の pane へ Ctrl+Space を送る。
local menu = { block_id = "m", label = "dotfiles-popup/prefix/a", placement = "placed" }
popup = setup({ anchor, menu })
popup.open({ session_id = "s", block_id = "m" }, "prefix")
eq(methods(skip), "block.close,session.focus_block", "prefix twice")
eq(queued[1][2].key, "ctrl+space", "send ctrl+space")

-- cwd が取れない、または手元に無い cwd では開かない。不明な kind も拒否する。
for _, case in ipairs({ { {}, "no cwd" }, { { cwd = "/container", is_dir = false }, "missing dir" } }) do
  popup = setup({ anchor }, case[1])
  eq(pcall(popup.open, { session_id = "s", block_id = "a" }, "git"), false, case[2])
end
eq(pcall(popup.open, { session_id = "s", block_id = "a" }, "typo"), false, "unknown")

print("ok")
