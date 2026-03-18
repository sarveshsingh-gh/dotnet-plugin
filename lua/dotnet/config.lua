local M = {}

M.defaults = {
  auto_find_sln = true,

  palette = {
    cmd   = "Dotnet",
    alias = "D",
  },

  explorer = {
    width       = 0.18,
    min_width   = 30,
    show_hidden = false,
    side        = "left",
  },

  test_explorer = {
    width = 0.22,
    side  = "right",
  },

  runner = {
    notify_on_success = true,
    terminal = {
      direction = "botright",
      size      = 15,
    },
  },

  dap = {
    enabled      = true,
    adapter_name = "coreclr",
    console      = "integratedTerminal",
    netcoredbg_paths = {
      vim.fn.expand("~/.local/share/nvim/mason/bin/netcoredbg"),
      vim.fn.exepath("netcoredbg"),
    },
    signs = {
      breakpoint          = { text = "●", color = "#E51400" },
      breakpoint_cond     = { text = "◆", color = "#FF8C00" },
      breakpoint_rejected = { text = "○", color = "#6D8086" },
      logpoint            = { text = "◉", color = "#61AFEF" },
      stopped             = { text = "▶", color = "#FFD700", linehl_bg = "#3B3800" },
    },
  },

  lsp = {
    roslyn = { enabled = true },
  },

  keymaps = {
    palette          = "<M-S-p>",
    find_file        = "<leader>nf",
    explorer_toggle  = "<leader>ne",
    explorer_reveal  = "<leader>nE",
    new_item         = "<leader>nn",
    fix_namespace    = "<leader>nns",
    list_jobs        = "<leader>nj",
    stop_all         = "<leader>nx",
    build_solution   = "<leader>nB",
    build_project    = "<leader>nb",
    build_quickfix   = "<leader>nQ",
    run_project      = "<leader>nr",
    watch            = "<leader>nw",
    test_solution    = "<leader>nts",
    test_project     = "<leader>nt",
    restore          = "<leader>nR",
    clean            = "<leader>nc",
    rebuild          = "<leader>nRb",
    test_explorer    = "<leader>te",
    nuget_add        = "<leader>npa",
    nuget_remove     = "<leader>npr",
    nuget_list       = "<leader>npl",
    nuget_outdated   = "<leader>npo",
    run_profile      = "<leader>nrp",
    debug_launch     = "<leader>nd",
    launch_settings  = "<leader>nL",
    run_func         = "<leader>naf",
    debug_func       = "<leader>naF",
    -- EF Core
    ef_migration_add    = "<leader>nema",
    ef_migration_remove = "<leader>nemr",
    ef_migration_list   = "<leader>neml",
    ef_migration_script = "<leader>nems",
    ef_db_update        = "<leader>nedu",
    ef_db_update_to     = "<leader>nedU",
    ef_db_drop          = "<leader>nedd",
    ef_scaffold         = "<leader>nesc",
  },
}

function M.resolve(user_opts)
  return vim.tbl_deep_extend("force", M.defaults, user_opts or {})
end

return M
