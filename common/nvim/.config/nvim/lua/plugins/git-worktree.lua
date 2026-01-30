return {
  -- telescope-repo: Jump between repositories/submodules
  {
    "cljoly/telescope-repo.nvim",
    dependencies = { "nvim-telescope/telescope.nvim" },
    keys = {
      {
        "<leader>gR",
        function()
          require("telescope").extensions.repo.list({})
        end,
        desc = "Git Repos/Submodules",
      },
    },
    config = function()
      require("telescope").load_extension("repo")
    end,
  },
}
