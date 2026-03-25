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
--   • mason registry            — adds Crashdummyy registry so roslyn is findable
--   • seblyng/roslyn.nvim       — C# LSP with inlay hints (var types, params)
--   • keymaps: t, dt (buffer), gx, <leader>nT/no/nl (global)

return {

  -- ── Mason: Crashdummyy registry (roslyn lives here) ──────────────────────
  {
    "mason-org/mason.nvim",
    opts_extend = { "ensure_installed" },
    opts = function(_, opts)
      -- preserve the default registry if none have been set yet
      opts.registries = opts.registries or { "github:mason-org/mason-registry" }
      local has = false
      for _, r in ipairs(opts.registries) do
        if r:find("Crashdummyy") then has = true; break end
      end
      if not has then
        table.insert(opts.registries, "github:Crashdummyy/mason-registry")
      end
      -- auto-install .NET tools (LazyVim's mason config reads ensure_installed)
      opts.ensure_installed = vim.list_extend(opts.ensure_installed or {}, {
        "roslyn",
        "netcoredbg",
      })
    end,
  },

  -- ── Roslyn: C# LSP + inlay hints + code lens ─────────────────────────────
  {
    "seblyng/roslyn.nvim",
    ft   = "cs",
    -- init runs at startup even for lazy plugins — settings must be registered
    -- before roslyn starts so workspace/configuration requests are answered correctly.
    init = function()
      vim.lsp.config("roslyn", {
        settings = {
          ["csharp|inlay_hints"] = {
            csharp_enable_inlay_hints_for_implicit_object_creation = true,
            csharp_enable_inlay_hints_for_implicit_variable_types  = true,
            csharp_enable_inlay_hints_for_lambda_parameter_types   = true,
            csharp_enable_inlay_hints_for_types                    = true,
            dotnet_enable_inlay_hints_for_indexer_parameters       = true,
            dotnet_enable_inlay_hints_for_literal_parameters       = true,
            dotnet_enable_inlay_hints_for_object_creation_parameters = true,
            dotnet_enable_inlay_hints_for_other_parameters         = true,
            dotnet_enable_inlay_hints_for_parameters               = true,
          },
          ["csharp|code_lens"] = {
            dotnet_enable_references_code_lens = true,
            dotnet_enable_tests_code_lens      = true,
          },
        },
      })
    end,
    config = function()
      require("roslyn").setup()

      -- Roslyn rejects inlay/codelens requests until the project is fully loaded.
      -- Re-request both once initialization completes.
      vim.api.nvim_create_autocmd("User", {
        pattern  = "RoslynInitialized",
        callback = function()
          vim.defer_fn(function()
            for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
              if vim.api.nvim_buf_is_valid(bufnr)
                and vim.bo[bufnr].filetype == "cs"
                and #vim.lsp.get_clients({ name = "roslyn", bufnr = bufnr }) > 0
              then
                vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
                vim.lsp.codelens.refresh()
              end
            end
          end, 500)
        end,
      })
    end,
  },

  -- ── Treesitter: C# parser (required by neotest-dotnet for test detection) ─
  {
    "nvim-treesitter/nvim-treesitter",
    opts_extend = { "ensure_installed" },
    opts = { ensure_installed = { "c_sharp" } },
  },

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
      "Issafalcon/neotest-dotnet",
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

      require("dotnet.commands.init").register("lsp.inlay_hints", {
        category = "lsp",
        icon     = "󰴑 ",
        desc     = "Toggle inlay hints",
        key      = "<leader>ci",
        run      = function()
          vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), { bufnr = 0 })
        end,
      })
    end,
  },

}
