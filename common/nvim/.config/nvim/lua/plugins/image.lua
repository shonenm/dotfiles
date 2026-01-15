return {
  "3rd/image.nvim",
  event = { "BufReadPre *.png,*.jpg,*.jpeg,*.gif,*.webp", "FileType markdown,norg" },
  opts = {
    backend = "kitty",
    integrations = {
      markdown = {
        enabled = true,
        clear_in_insert_mode = true,
        only_render_image_at_cursor = true,
      },
    },
    max_width = 100,
    max_height = 30,
    max_height_window_percentage = 50,
    window_overlap_clear_enabled = true,
    hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp" },
  },
}
