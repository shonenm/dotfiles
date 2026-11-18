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

local function action(name, title, command, kind)
  rex.action{
    name = name,
    title = title,
    category = "Dotfiles",
    run = function(ctx)
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
for _, entry in ipairs({
  { "h", "client.tab.previous" }, { "l", "client.tab.next" },
  { "k", "session.previous" }, { "j", "session.next" },
}) do
  rex.bind("ctrl+alt+" .. entry[1], entry[2])
end
-- Ctrl+h/j/k/l は vim-rex-navigator。vim/nvim が前面の pane では Neovim に渡す。
-- plugin は渡す先を vim/nvim に固定しているため、ssh 先 (rcon の nvim / tmux) へ渡す判定を binding の前に挟む。
local bind = rex.bind
rex.bind = function(key, action, args)
  if type(action) ~= "function" then return bind(key, action, args) end
  return bind(key, function(ctx)
    local process = rex.block.call("com.superlogical.terminal", "process", { block_id = ctx.block_id })
    local fg = process and process.foreground
    if fg and (fg.name == "ssh" or fg.argv0 == "ssh") then return false end
    return action(ctx)
  end, args)
end
plugin("vim-rex-navigator")
rex.bind = bind
-- Rex に copy mode がないため、prefix v / [ で pane の scrollback を tmux の copy mode で開く。
-- copy mode 内の key は tmux-copy.conf。prefix C-u は tmux 時代と同じく半ページ戻った状態で開く。
local copy_mode
local define = rex.action
rex.action = function(spec)
  if spec.name == "tmux_copy_mode" then copy_mode = spec.run end
  return define(spec)
end
plugin("rex-tmux-copy", { key = "ctrl+space>v" })
rex.action = define
if copy_mode then
  rex.bind("ctrl+space>[", "tmux_copy_mode")
  rex.action{
    name = "dotfiles_copy_halfpage",
    title = "Copy Mode (tmux): Half Page Up",
    category = "Dotfiles",
    run = function(ctx)
      -- plugin は起動 command を受け取らないため、作成される block の command に印を付ける。
      local block = rex.layout.block
      rex.layout.block = function(spec)
        spec.options.command = { "env", "REX_TMUX_COPY_HALFPAGE=1", unpack(spec.options.command) }
        return block(spec)
      end
      local ok, err = pcall(copy_mode, ctx)
      rex.layout.block = block
      if not ok then error(err, 0) end
    end,
  }
  rex.bind("ctrl+space>ctrl+u", "dotfiles_copy_halfpage")
end
