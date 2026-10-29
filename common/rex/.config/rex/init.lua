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
rex.bind("ctrl+space", "dotfiles_prefix")

for _, entry in ipairs({
  { "git", "Lazygit" }, { "pr", "Live PR" }, { "editor", "Neovim" },
  { "database", "PostgreSQL" }, { "ports", "Quay" },
  { "scratch", "Scratch Shell" }, { "metadata", "Metadata" },
  { "project", "Project Picker" }, { "layout", "Layout Presets" },
}) do
  action("dotfiles_" .. entry[1], "Dotfiles: " .. entry[2], "popup", entry[1])
end
-- Ctrl+h/j/k/l は Neovim の入力を奪わない。移動は prefix メニューから。
