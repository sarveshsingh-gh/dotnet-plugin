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
-- Everything below is auto-installed and auto-configured:
--   • Roslyn      — C# LSP (go-to-def, hover, rename, diagnostics…)
--   • netcoredbg  — .NET debugger
--   • nvim-dap + dap-ui + dap-virtual-text  — debugging UI
--   • neotest + neotest-dotnet  — class / method / file-aware test running
--   • dotnet.nvim itself  — build, run, solution explorer, test explorer…
--   • Mason        — auto-installs roslyn + netcoredbg
--
-- You can override any individual spec from your own config — lazy.nvim
-- merges specs for the same plugin, so your opts/config take precedence.

return {

  -- ── shared async library ─────────────────────────────────────────────────
  { "nvim-neotest/nvim-nio", lazy = true },

  -- ── Roslyn: C# LSP ───────────────────────────────────────────────────────
  {
    "seblyng/roslyn.nvim",
    ft = "cs",
  },

  -- ── Mason: auto-install roslyn + netcoredbg ───────────────────────────────
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.registries = opts.registries or {}
      -- Crashdummyy registry provides the "roslyn" mason package
      local has_crashdummyy = false
      for _, r in ipairs(opts.registries) do
        if r:find("Crashdummyy") then has_crashdummyy = true; break end
      end
      if not has_crashdummyy then
        table.insert(opts.registries, "github:Crashdummyy/mason-registry")
      end
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "roslyn", "netcoredbg" })
    end,
  },

  -- ── nvim-dap: debug adapter core ─────────────────────────────────────────
  {
    "mfussenegger/nvim-dap",
    lazy = true,
    config = function()
      -- VS-style breakpoint signs (colours/icons)
      require("dotnet.dap.signs").setup()
    end,
  },

  -- ── nvim-dap-ui: debugger panels ─────────────────────────────────────────
  {
    "rcarriga/nvim-dap-ui",
    dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
    config = function()
      local dap, dapui = require("dap"), require("dapui")
      dapui.setup({
        expand_lines = true,
        controls     = { enabled = false },
        floating     = { border = "rounded" },
        render       = { max_type_length = 60, max_value_lines = 200 },
        layouts = {
          {
            elements = {
              { id = "scopes",      size = 0.5  },
              { id = "breakpoints", size = 0.25 },
              { id = "stacks",      size = 0.25 },
            },
            size = 15, position = "bottom",
          },
          {
            elements = { { id = "watches", size = 1.0 } },
            size = 15, position = "bottom",
          },
        },
      })
      dap.listeners.after.event_initialized["dapui_config"] = function() dapui.open() end
      dap.listeners.before.event_terminated["dapui_config"] = function() dapui.close() end
      dap.listeners.before.event_exited["dapui_config"]     = function() dapui.close() end
    end,
  },

  -- ── nvim-dap-virtual-text: variable values inline ────────────────────────
  {
    "theHamsta/nvim-dap-virtual-text",
    dependencies = { "mfussenegger/nvim-dap" },
    opts = {
      commented                   = true,
      highlight_changed_variables = true,
    },
  },

  -- ── telescope-dap: browse breakpoints / frames via Telescope ─────────────
  {
    "nvim-telescope/telescope-dap.nvim",
    dependencies = {
      "nvim-telescope/telescope.nvim",
      "mfussenegger/nvim-dap",
    },
    config = function()
      require("telescope").load_extension("dap")
    end,
  },

  -- ── neotest + neotest-dotnet ──────────────────────────────────────────────
  -- Provides class / method / file-aware test running + debug.
  --
  -- dotnet.nvim unconditionally sets t / dt buffer keymaps via a FileType cs
  -- autocmd.  This spec lists dotnet.nvim as a dependency so it initialises
  -- first, then registers its own FileType cs autocmd immediately after.
  -- Neovim fires autocmds in registration order, so neotest's runs last and
  -- its keymap.set calls overwrite dotnet.nvim's on every .cs buffer open.
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "Nsidorenco/neotest-dotnet",
      "sarveshsingh-gh/dotnet-plugin",  -- must be initialised before this config runs
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

      -- gx: open job log picker (background build/test/run jobs)
      vim.keymap.set("n", "gx", function() require("dotnet.telescope.jobs").open() end,
        { desc = "Dotnet job log" })
    end,
  },

}
