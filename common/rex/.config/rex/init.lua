-- dotfiles: ローカル Rex の popup とメタデータ一覧。
local helper = os.getenv("HOME") .. "/dotfiles/scripts/rex-tools"

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
-- Ctrl+h/j/k/l は Neovim の入力を奪わない。移動は native prefix 経由。
