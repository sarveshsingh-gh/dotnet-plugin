-- dotnet.nvim — entry point
-- require("dotnet").setup(opts)
local M = {}

local _cfg = nil

function M.setup(user_opts)
  _cfg = require("dotnet.config").resolve(user_opts)

  -- Load all command modules (they self-register into commands.init)
  require("dotnet.commands.build")
  require("dotnet.commands.run")
  require("dotnet.commands.test")
  require("dotnet.commands.solution")
  require("dotnet.commands.file")
  require("dotnet.commands.nuget")

  -- Register jobs + files commands in palette
  local cmd = require("dotnet.commands.init")
  cmd.register("jobs.list", {
    category = "run",
    icon     = "󰒖 ",
    desc     = "List running processes",
    run      = function() require("dotnet.telescope.jobs").open() end,
  })
  cmd.register("files.find", {
    category = "file",
    icon     = " ",
    desc     = "Find file in solution",
    run      = function() require("dotnet.telescope.files").open() end,
  })
  cmd.register("explorer.toggle", {
    category = "file",
    icon     = "󰙅 ",
    desc     = "Toggle Solution Explorer",
    run      = function() require("dotnet.ui.explorer").toggle() end,
  })
  cmd.register("explorer.reveal", {
    category = "file",
    icon     = "󰙅 ",
    desc     = "Reveal current file in Explorer",
    run      = function() require("dotnet.ui.explorer").reveal() end,
  })
  cmd.register("test_explorer.toggle", {
    category = "test",
    icon     = "󰙨 ",
    desc     = "Toggle Test Explorer",
    run      = function() require("dotnet.ui.test_explorer").toggle() end,
  })

  -- DAP setup
  require("dotnet.dap.init").setup(_cfg.dap)

  -- Keymaps
  require("dotnet.keymaps").setup(_cfg.keymaps)

  -- :Dotnet and :D commands
  local palette_cmd = (_cfg.palette or {}).cmd or "Dotnet"
  local palette_alias = (_cfg.palette or {}).alias or "D"
  vim.api.nvim_create_user_command(palette_cmd, function()
    require("dotnet.ui.palette").open()
  end, { desc = "Dotnet command palette" })
  pcall(vim.api.nvim_create_user_command, palette_alias, function()
    require("dotnet.ui.palette").open()
  end, { desc = "Dotnet command palette" })

  -- Auto-find solution
  if _cfg.auto_find_sln then
    vim.schedule(function()
      local sln = require("dotnet.core.solution").find()
      if sln then
        require("dotnet.ui.explorer").set_sln(sln)
        require("dotnet.ui.test_explorer").set_sln(sln)
        require("dotnet.notify").info("Solution: " .. vim.fn.fnamemodify(sln, ":t"))
      end
    end)
  end
end

--- Access resolved config from anywhere.
function M.config() return _cfg end

return M
