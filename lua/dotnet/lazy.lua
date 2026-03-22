-- lua/dotnet/lazy.lua
--
-- Importable lazy.nvim spec that turns dotnet.nvim into a full .NET IDE.
--
-- Usage — add ONE line to your lazy.nvim setup:
--
--   require("lazy").setup({
--     { import = "dotnet.lazy" },
--   })
--
-- Prerequisites (install separately — dotnet.lazy does NOT configure these
-- so it never conflicts with your own setup):
--   • nvim-dap + nvim-dap-ui   debugging
--   • nvim-telescope/telescope.nvim
--   • mason-org/mason.nvim     (include "roslyn" + "netcoredbg" in ensure_installed
--                               and add "github:Crashdummyy/mason-registry")
--   • seblyng/roslyn.nvim      C# LSP
--
-- What this file DOES install and configure:
--   • neotest + neotest-dotnet  — class / method / file-aware test running
--   • dotnet.nvim itself        — build, run, solution/test explorer, DAP…
--   • keymaps: t, dt (buffer), gx, <leader>nT/no/nl (global)

return {

  -- ── neotest + neotest-dotnet ──────────────────────────────────────────────
  -- dotnet.nvim unconditionally sets t / dt via a FileType cs autocmd.
  -- This spec lists dotnet.nvim as a dependency so lazy initialises it first,
  -- then registers its own FileType cs autocmd immediately after.
  -- Neovim runs autocmds in registration order → neotest's fires last → wins.
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "Nsidorenco/neotest-dotnet",
      "sarveshsingh-gh/dotnet-plugin",  -- must initialise before this config
    },
    config = function()
      require("neotest").setup({
        adapters = {
          require("neotest-dotnet")({
            dap = {
              args         = { justMyCode = false },
              adapter_name = "coreclr",
            },
          }),
        },
        output       = { open_on_run = false },
        output_panel = { open_on_run = false },
        status       = { virtual_text = true, signs = true },
      })

      -- Override dotnet.nvim's t / dt with neotest-powered versions.
      -- Registered after dotnet.nvim's autocmd → fires last → wins.
      vim.api.nvim_create_autocmd("FileType", {
        pattern  = "cs",
        callback = function(ev)
          local n = require("neotest")
          -- t  : cursor in method → that method
          --      cursor in class  → whole class
          --      elsewhere        → whole file
          vim.keymap.set("n", "t", function() n.run.run() end,
            { buffer = ev.buf, desc = "Test run nearest" })
          -- dt : same scoping but launches via DAP (breakpoints respected)
          vim.keymap.set("n", "dt", function() n.run.run({ strategy = "dap" }) end,
            { buffer = ev.buf, desc = "Test debug nearest" })
        end,
      })

      -- Neotest global keymaps
      local map = vim.keymap.set
      map("n", "<leader>nT", function() require("neotest").summary.toggle() end,      { desc = "Neotest summary toggle" })
      map("n", "<leader>no", function() require("neotest").output_panel.toggle() end, { desc = "Neotest output panel" })
      map("n", "<leader>nl", function() require("neotest").run.run_last() end,        { desc = "Neotest run last" })
    end,
  },

  -- ── dotnet.nvim: the .NET IDE core ───────────────────────────────────────
  {
    "sarveshsingh-gh/dotnet-plugin",
    name  = "dotnet.nvim",
    event = "VeryLazy",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
      "mfussenegger/nvim-dap",
      "rcarriga/nvim-dap-ui",
      "nvim-neotest/nvim-nio",
    },
    config = function()
      local is_win    = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
      local mason_bin = is_win
        and vim.fn.expand("~/AppData/Local/nvim-data/mason/packages/netcoredbg/netcoredbg/netcoredbg.exe")
        or  vim.fn.expand("~/.local/share/nvim/mason/bin/netcoredbg")

      require("dotnet").setup({
        dap = {
          netcoredbg_paths = {
            mason_bin,
            vim.fn.exepath("netcoredbg"),
          },
        },
      })

      -- gx: open job log picker (background build / test / run jobs)
      vim.keymap.set("n", "gx", function() require("dotnet.telescope.jobs").open() end,
        { desc = "Dotnet job log" })
    end,
  },

}
