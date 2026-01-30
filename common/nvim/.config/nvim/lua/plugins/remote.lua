-- Remote/container development (VSCode Dev Containers equivalent)
return {
  {
    "amitds1997/remote-nvim.nvim",
    version = "*",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-telescope/telescope.nvim",
    },
    cmd = {
      "RemoteStart",
      "RemoteStop",
      "RemoteInfo",
      "RemoteCleanup",
      "RemoteConfigDel",
      "RemoteLog",
    },
    keys = {
      { "<leader>Rs", "<cmd>RemoteStart<cr>", desc = "Remote: Start" },
      { "<leader>Ri", "<cmd>RemoteInfo<cr>", desc = "Remote: Info" },
      { "<leader>Rx", "<cmd>RemoteStop<cr>", desc = "Remote: Stop" },
      { "<leader>Rl", "<cmd>RemoteLog<cr>", desc = "Remote: Log" },
    },
    opts = {},
  },
}
