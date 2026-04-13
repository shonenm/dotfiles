-- Force remote-image mode on Linux (Docker/SSH).
-- Ghostty runs on the Mac host while Neovim runs inside a container or remote
-- shell, so terminal-side file paths (t=f) never resolve. SNACKS_SSH=1 forces
-- snacks.nvim to embed image data as base64 instead. On macOS (local Ghostty),
-- leave it unset so the faster file-path transport is used.
if vim.fn.has("mac") == 0 then
  vim.env.SNACKS_SSH = "1"
end

-- Patch snacks.image.placement:update() for two issues that break re-entry:
--
-- 1. `hidden` flag is never cleared on re-entry. snacks auto-calls `hide()`
--    when `state.wins == 0` (BufLeave), setting `self.hidden = true`. But it
--    never auto-calls `show()` on BufEnter, so `_render()` strips virt_text
--    (placeholder chars) and the terminal loses the cue to draw the image.
-- 2. `_state` cache causes early-return on identical window geometry. Inside
--    tmux, pane/buffer redraws clear Kitty Graphics placements in the terminal,
--    so the placement request must be re-sent even when state is unchanged.
--
-- Clearing `hidden` and `_state` before the original update() fixes both.
-- Image data is cached by the `sent` flag, so only the lightweight placement
-- command is re-transmitted.
local function patch_placement_redraw()
  local ok, placement = pcall(require, "snacks.image.placement")
  if not ok or placement._tmux_redraw_patched then
    return
  end
  placement._tmux_redraw_patched = true
  local orig_update = placement.update
  placement.update = function(self)
    self.hidden = false
    self._state = nil
    return orig_update(self)
  end
end

return {
  -- Disable 3rd/image.nvim (replaced by snacks.nvim image module)
  { "3rd/image.nvim", enabled = false },

  -- Enable snacks.nvim image module (SSH auto-detection, floating preview)
  {
    "folke/snacks.nvim",
    opts = {
      image = {
        enabled = true,
        doc = {
          enabled = true,
          inline = true,
          float = true,
          max_width = 80,
          max_height = 30,
        },
      },
    },
    init = function()
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        once = true,
        callback = patch_placement_redraw,
      })
    end,
  },
}
