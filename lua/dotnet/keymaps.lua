-- Global keymaps — only set up after setup() is called.
local M = {}

function M.setup(km)
  if not km then return end
  local map = vim.keymap.set

  local function bind(key, fn, desc)
    if key then map("n", key, fn, { desc = desc }) end
  end

  local dotnet = require("dotnet")

  bind(km.palette,         function() require("dotnet.ui.palette").open() end,               "Dotnet command palette")
  bind(km.explorer_toggle, function() require("dotnet.ui.explorer").toggle() end,            "Dotnet explorer toggle")
  bind(km.explorer_reveal, function() require("dotnet.ui.explorer").reveal() end,            "Dotnet explorer reveal file")
  bind(km.new_item,        function() require("dotnet.commands.init").run("file.new_item") end, "Dotnet new item")
  bind(km.fix_namespace,   function() require("dotnet.commands.init").run("file.fix_namespace") end, "Dotnet fix namespace")
  bind(km.list_jobs,       function() require("dotnet.telescope.jobs").open() end,           "Dotnet list jobs")
  bind(km.stop_all,        function() require("dotnet.core.runner").stop_all() end,          "Dotnet stop all")
  bind(km.build_solution,  function() require("dotnet.commands.init").run("build.solution") end,  "Dotnet build")
  bind(km.build_quickfix,  function() require("dotnet.commands.init").run("build.quickfix") end,  "Dotnet build quickfix")
  bind(km.run_project,     function() require("dotnet.commands.init").run("run.project") end,     "Dotnet run")
  bind(km.watch,           function() require("dotnet.commands.init").run("run.watch") end,       "Dotnet watch")
  bind(km.test_solution,   function() require("dotnet.commands.init").run("test.solution") end,   "Dotnet test solution")
  bind(km.test_project,    function() require("dotnet.commands.init").run("test.project") end,    "Dotnet test project")
  bind(km.restore,         function() require("dotnet.commands.init").run("build.restore") end,   "Dotnet restore")
  bind(km.clean,           function() require("dotnet.commands.init").run("build.clean") end,     "Dotnet clean")
  bind(km.rebuild,         function() require("dotnet.commands.init").run("build.rebuild") end,   "Dotnet rebuild")
  bind(km.test_explorer,   function() require("dotnet.ui.test_explorer").toggle() end,            "Dotnet test explorer")
  bind(km.nuget_add,       function() require("dotnet.commands.init").run("nuget.add") end,       "Dotnet NuGet add")
  bind(km.nuget_remove,    function() require("dotnet.commands.init").run("nuget.remove") end,    "Dotnet NuGet remove")

  -- VS-style debug F-keys
  local ok, dap = pcall(require, "dap")
  if ok then
    map("n", "<F5>",    function() dap.continue() end,         { desc = "Debug continue" })
    map("n", "<S-F5>",  function() dap.terminate() end,        { desc = "Debug stop" })
    map("n", "<F9>",    function() dap.toggle_breakpoint() end, { desc = "Debug breakpoint" })
    map("n", "<F10>",   function() dap.step_over() end,        { desc = "Debug step over" })
    map("n", "<F11>",   function() dap.step_into() end,        { desc = "Debug step into" })
    map("n", "<S-F11>", function() dap.step_out() end,         { desc = "Debug step out" })
  end
  local ok_ui, dapui = pcall(require, "dapui")
  if ok_ui then
    map({ "n", "v" }, "<S-F9>", function() dapui.eval() end,              { desc = "Debug QuickWatch" })
    map({ "n", "v" }, "<M-i>",  function() dapui.eval(nil, { enter=true }) end, { desc = "Debug Watch" })
  end
end

return M
