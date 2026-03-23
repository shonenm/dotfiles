-- .env file support (filetype detection for .env variants)
return {
  {
    "LazyVim/LazyVim",
    opts = function()
      vim.filetype.add({
        filename = {
          [".env"] = "dotenv",
          [".env.local"] = "dotenv",
          [".env.development"] = "dotenv",
          [".env.production"] = "dotenv",
          [".env.staging"] = "dotenv",
          [".env.e2e"] = "dotenv",
          [".env.test"] = "dotenv",
        },
        pattern = {
          ["%.env%.[%w_.-]+"] = "dotenv",
        },
      })
    end,
  },
}
