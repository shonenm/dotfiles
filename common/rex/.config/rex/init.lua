-- dotfiles: ローカル Rex の popup とメタデータ一覧。
local helper = os.getenv("HOME") .. "/dotfiles/scripts/rex-tools"

-- plugins.txt の plugin を scripts/rex-plugins sync の取得先から require できるようにする。
-- package.path の先頭はこの設定ファイルのディレクトリ。
local config_dir = package.path:match("^(.-)/%?%.lua;")
local plugin_dir = (os.getenv("XDG_DATA_HOME") or os.getenv("HOME") .. "/.local/share") .. "/rex/plugins/"
-- repo 直下の init.lua は repo 名で require する。
package.path = plugin_dir .. "?/init.lua;" .. package.path
for line in io.lines(config_dir .. "/plugins.txt") do
  local name, luadir = line:match("^([^#%s]%S*)%s+%S+%s+%S+%s+(%S+)")
  if name then
    local root = plugin_dir .. name .. "/" .. luadir
    package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
  end
end

-- 未取得の plugin で設定全体を失わないよう、警告して読み飛ばす。
local function plugin(module, opts)
  local ok, mod = pcall(require, module)
  if not ok then
    rex.log("warn", "plugin " .. module .. " を読み込めません。rex-plugins sync を実行してください: " .. tostring(mod))
    return
  end
  if mod.setup then mod.setup(opts) end
  return mod
end

-- floating popup は popup.lua が local / remote host とも server の接続から直接作る。
local popup = require("popup")

-- remote host の session（ctx.server が host）では、手元の CLI から ssh で繋ぎ直さず
-- server の接続で host 側に短命の pane を開き、host の dotfiles の rex-tools に任せる。
local function remote_popup(ctx, command, kind)
  local server = rex.server(ctx.server)
  -- host への接続は session に attach しないと session の操作を受け付けない。
  assert(server.call("session.attach", { session_id = ctx.session_id }))
  local list = assert(server.call("session.list_blocks", { session_id = ctx.session_id }))
  local window
  for _, b in ipairs(list.blocks) do
    if b.block_id == ctx.block_id then window = b.window_id end
  end
  if not window then error("呼出元 pane が表示されていません", 0) end
  local _, err = server.call("session.new_layer", {
    session_id = ctx.session_id, window_id = window, bounds = { .1, .4, .8, .2 }, focus = true,
    -- dotfiles-popup/ の label にして、swap の候補や origin の解決で popup として扱わせる。
    layout = { block = { flavor = "com.superlogical.terminal.shell", label = "dotfiles-popup/launcher/" .. ctx.block_id,
      options = {
        -- 失敗したら閉じる前に理由を読めるようにする。
        command = { "sh", "-c", '"$HOME/dotfiles/scripts/rex-tools" "$@" || read -r _',
          "rex-tools", command, kind, "--session", ctx.session_id, "--block", ctx.block_id },
      } } },
  })
  if err then error(err, 0) end
end

local function action(name, title, command, kind)
  rex.action{
    name = name,
    title = title,
    category = "Dotfiles",
    run = function(ctx)
      if command == "popup" then return popup.open(ctx, kind) end
      if ctx.server then return remote_popup(ctx, command, kind) end
      local argv = { helper, command, kind, "--session", ctx.session_id,
        "--block", ctx.block_id }
      if ctx.client_id then
        table.insert(argv, "--client")
        table.insert(argv, ctx.client_id)
      end
      local result, err = rex.exec(argv)
      if not result then error(err) end
      if not result.ok then error(result.stderr) end
    end,
  }
end

action("dotfiles_prefix", "Dotfiles: Prefix Menu", "popup", "prefix")
-- prefix の入力待機は client 内で処理し、Python / popup の起動を待たない。
rex.bind("ctrl+space>shift+/", "dotfiles_prefix")
rex.bind("ctrl+space>ctrl+space", "pane.send_key", { key = "ctrl+space" })

for _, entry in ipairs({
  { "git", "Lazygit", "g" }, { "pr", "Live PR", "shift+g" }, { "editor", "Neovim", "k" },
  { "database", "PostgreSQL", "shift+p" }, { "ports", "Quay", "shift+q" },
  { "scratch", "Scratch Shell", "j" }, { "metadata", "Metadata", "shift+a" },
  { "project", "Project Picker", "shift+f" }, { "layout", "Layout Presets", "l" },
  { "swap", "Swap Panes", "m" },
}) do
  action("dotfiles_" .. entry[1], "Dotfiles: " .. entry[2], "popup", entry[1])
  rex.bind("ctrl+space>" .. entry[3], "dotfiles_" .. entry[1])
end

action("dotfiles_dev", "Dotfiles: Dev Template", "view", "dev")
rex.bind("ctrl+space>shift+n", "dotfiles_dev")
for _, entry in ipairs({
  { "c", "client.tab.new" }, { "n", "client.tab.next" }, { "p", "client.tab.previous" },
  { "z", "pane.zoom" }, { "s", "session.switch" }, { "f", "session.switch" },
  { "a", "client.sidebar.activity.toggle" }, { "r", "client.config.reload" },
  { "shift+\\", "pane.split", { direction = "right" } },
  { "-", "pane.split", { direction = "down" } },
  { "h", "pane.focus", { direction = "left" } },
}) do
  rex.bind("ctrl+space>" .. entry[1], entry[2], entry[3])
end
for _, entry in ipairs({ { "h", "left" }, { "j", "down" }, { "k", "up" }, { "l", "right" } }) do
  rex.bind("ctrl+space>ctrl+" .. entry[1], "pane.focus", { direction = entry[2] })
  rex.bind("ctrl+space>shift+" .. entry[1], "pane.resize", { direction = entry[2], amount = 2 })
end
-- tmux の session group 移動と同じ指使い。Ctrl+Option+h/l は tab、j/k は session を巡回する。
-- client.tab.next/previous は session の端で隣の session の tab へ進むため、端では逆方向へ tab 数 - 1 回進めて反対の端へ移る。
-- client.tab.goto の index は session 内ではなく client 全体の tab の通し番号なので、端の移動には使えない。
-- 表示中の tab は client が持ち、server の active window を変えても追従しないため client action を使う。
for _, entry in ipairs({ { "previous", "Previous", 1, "next" }, { "next", "Next", -1, "previous" } }) do
  local name, title, edge, opposite = entry[1], entry[2], entry[3], entry[4]
  rex.action{
    name = "dotfiles_tab_" .. name,
    title = "Dotfiles: " .. title .. " Tab in Session",
    category = "Dotfiles",
    run = function(ctx)
      -- remote host の session は手元の server に無いため、host の接続で attach してから引く。
      local server = rex
      if ctx.server then
        server = rex.server(ctx.server)
        assert(server.call("session.attach", { session_id = ctx.session_id }))
      end
      local view, err = server.call("session.view", { session_id = ctx.session_id })
      if not view then error(err) end
      local windows, index = view.windows, nil
      for i, window in ipairs(windows) do
        for _, layer in ipairs(window.layers) do
          for _, block in ipairs(layer.blocks) do
            if block.block_id == ctx.block_id then index = i end
          end
        end
      end
      if not index then error("focused block の window が見つかりません") end
      -- edge は端の tab 位置 (1 = 先頭, -1 = 最後)。
      local at_edge = (edge == 1 and index == 1) or (edge == -1 and index == #windows)
      if at_edge then
        for _ = 2, #windows do rex.client.queue("client.tab." .. opposite) end
      else
        rex.client.queue("client.tab." .. name)
      end
    end,
  }
end
for _, entry in ipairs({
  { "h", "dotfiles_tab_previous" }, { "l", "dotfiles_tab_next" },
  { "k", "session.previous" }, { "j", "session.next" },
}) do
  rex.bind("ctrl+alt+" .. entry[1], entry[2])
end
-- Ctrl+h/j/k/l で pane を移動する。vim/nvim と ssh (rcon のリモート nvim / tmux) が前面の pane ではキーを渡し、
-- Neovim は内部 split を先に移動して端で同じ pane.focus を呼ぶ (common/nvim/.config/nvim/lua/plugins/tmux-navigator.lua)。
-- server の session.focus_direction で動かすと app が覚える focus が更新されず、session を離れて戻ると
-- 前の pane に戻るため、app の pane.focus で動かす。
-- key handler の関数からは client action を queue できないため action にし、渡す場合は pane.send_key で送る。
local pass_keys = { vim = true, nvim = true, view = true, vimdiff = true, ssh = true }
for key, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  rex.action{
    name = "dotfiles_focus_" .. direction,
    title = "Dotfiles: Focus Pane " .. direction,
    category = "Dotfiles",
    run = function(ctx)
      local ok, process = pcall(rex.block.call, "com.superlogical.terminal", "process", { block_id = ctx.block_id })
      local fg = ok and process and process.foreground
      if fg and (pass_keys[fg.name] or pass_keys[fg.argv0]) then
        rex.client.queue("pane.send_key", { key = "ctrl+" .. key })
      else
        rex.client.queue("pane.focus", { direction = direction })
      end
    end,
  }
  rex.bind("ctrl+" .. key, "dotfiles_focus_" .. direction)
end
-- Rex に copy mode がないため、prefix v / [ で pane の scrollback を tmux の copy mode で開く。
-- copy mode 内の key は tmux-copy.conf。prefix C-u は tmux 時代と同じく半ページ戻った状態で開く。
local copy_mode
local define = rex.action
rex.action = function(spec)
  if spec.name == "tmux_copy_mode" then copy_mode = spec.run end
  return define(spec)
end
plugin("rex-tmux-copy", { key = false })
rex.action = define
if copy_mode then
  -- plugin は起動 command を受け取らないため、作成される block の command を包む。
  -- copy mode の pane は login shell を通らず server の PATH で動く。remote host の server は
  -- PATH に ~/.local/bin を含まず、そこにある rex / tmux が見つからず即終了するため足す。
  local function copy_action(name, title, env)
    rex.action{
      name = name,
      title = title,
      category = "Dotfiles",
      run = function(ctx)
        local block = rex.layout.block
        rex.layout.block = function(spec)
          spec.options.command = { "sh", "-c", 'PATH="$HOME/.local/bin:$PATH" exec env "$@"', "sh",
            env, unpack(spec.options.command) }
          return block(spec)
        end
        local ok, err = pcall(copy_mode, ctx)
        rex.layout.block = block
        if not ok then error(err, 0) end
      end,
    }
  end
  copy_action("dotfiles_copy_mode", "Copy Mode (tmux)", "REX_TMUX_COPY_HALFPAGE=")
  copy_action("dotfiles_copy_halfpage", "Copy Mode (tmux): Half Page Up", "REX_TMUX_COPY_HALFPAGE=1")
  rex.bind("ctrl+space>v", "dotfiles_copy_mode")
  rex.bind("ctrl+space>[", "dotfiles_copy_mode")
  rex.bind("ctrl+space>ctrl+u", "dotfiles_copy_halfpage")
end

-- rexurrect: server 起動時に前回の snapshot を復元する (保存は launchd の autosave)。
-- server は bare な環境で動くため、本体の path と state / config の場所を明示する。
do
  local bin = "/opt/homebrew/bin/rexurrect"
  local f = io.open(bin)
  if f then
    f:close()
    local home = os.getenv("HOME")
    local r = rex.exec({ bin, "auto-restore" }, { env = {
      REXURRECT_STATE_DIR = (os.getenv("XDG_STATE_HOME") or home .. "/.local/state") .. "/rexurrect",
      REXURRECT_CONFIG = (os.getenv("XDG_CONFIG_HOME") or home .. "/.config") .. "/rexurrect/config.toml",
    } })
    if r then io.stderr:write(r.stderr) end
  end
end
