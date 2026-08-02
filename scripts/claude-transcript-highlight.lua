-- Make user prompts immediately distinguishable in the read-only transcript.
-- Extmarks affect display only: yanked text remains the original Markdown.

local buffer = vim.api.nvim_get_current_buf()
local namespace = vim.api.nvim_create_namespace("claude-transcript-user")
local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
local in_user_prompt = false

vim.api.nvim_set_hl(0, "ClaudeTranscriptUser", { link = "DiffAdd", default = true })
vim.api.nvim_set_hl(0, "ClaudeTranscriptUserHeader", { link = "DiffText", default = true })

for index, line in ipairs(lines) do
  if line == "# USER PROMPT" then
    in_user_prompt = true
  elseif line == "# CLAUDE" then
    in_user_prompt = false
  end

  if in_user_prompt then
    vim.api.nvim_buf_set_extmark(buffer, namespace, index - 1, 0, {
      line_hl_group = line == "# USER PROMPT"
          and "ClaudeTranscriptUserHeader"
        or "ClaudeTranscriptUser",
      priority = 120,
    })
  end
end
