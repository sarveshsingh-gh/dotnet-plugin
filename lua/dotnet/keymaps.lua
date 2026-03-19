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
  bind(km.find_file,       function() require("dotnet.telescope.files").open() end,          "Dotnet find file in solution")
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
  bind(km.remove_project,  function() require("dotnet.commands.init").run("solution.remove_project") end, "Dotnet remove project from solution")
  bind(km.nuget_add,       function() require("dotnet.commands.init").run("nuget.add") end,       "Dotnet NuGet add")
  bind(km.nuget_remove,    function() require("dotnet.commands.init").run("nuget.remove") end,    "Dotnet NuGet remove")
  bind(km.nuget_list,      function() require("dotnet.commands.init").run("nuget.list") end,      "Dotnet NuGet list")
  bind(km.nuget_outdated,  function() require("dotnet.commands.init").run("nuget.outdated") end,  "Dotnet NuGet outdated")
  bind(km.run_profile,     function() require("dotnet.commands.init").run("run.profile") end,     "Dotnet run with launch profile")
  -- Docker
  bind(km.docker_scaffold,         function() require("dotnet.commands.init").run("docker.scaffold") end,         "Docker scaffold Dockerfile")
  bind(km.docker_scaffold_all,     function() require("dotnet.commands.init").run("docker.scaffold_all") end,     "Docker scaffold all Dockerfiles")
  bind(km.docker_scaffold_debug,   function() require("dotnet.commands.init").run("docker.scaffold_debug") end,   "Docker scaffold Dockerfile.debug")
  bind(km.docker_compose_open,     function() require("dotnet.commands.init").run("docker.compose_open") end,     "Docker open service in browser")
  bind(km.docker_compose_scaffold, function() require("dotnet.commands.init").run("docker.compose_scaffold") end, "Docker scaffold docker-compose.yml")
  bind(km.docker_build,        function() require("dotnet.commands.init").run("docker.build") end,         "Docker build image")
  bind(km.docker_run,          function() require("dotnet.commands.init").run("docker.run") end,           "Docker run container")
  bind(km.docker_ls,           function() require("dotnet.commands.init").run("docker.ls") end,            "Docker list containers")
  bind(km.docker_attach,       function() require("dotnet.commands.init").run("docker.attach") end,        "Docker attach debugger")
  bind(km.docker_compose_add_db, function() require("dotnet.commands.init").run("docker.compose_add_db") end, "Docker compose add database")
  bind(km.docker_compose_up,   function() require("dotnet.commands.init").run("docker.compose_up") end,    "Docker compose up")
  bind(km.docker_compose_down, function() require("dotnet.commands.init").run("docker.compose_down") end,  "Docker compose down")
  bind(km.docker_compose_logs, function() require("dotnet.commands.init").run("docker.compose_logs") end,  "Docker compose logs")
  -- EF Core
  bind(km.ef_migration_add,    function() require("dotnet.commands.init").run("ef.migration.add") end,    "EF add migration")
  bind(km.ef_migration_remove, function() require("dotnet.commands.init").run("ef.migration.remove") end, "EF remove last migration")
  bind(km.ef_migration_list,   function() require("dotnet.commands.init").run("ef.migration.list") end,   "EF list migrations")
  bind(km.ef_migration_script, function() require("dotnet.commands.init").run("ef.migration.script") end, "EF generate SQL script")
  bind(km.ef_db_update,        function() require("dotnet.commands.init").run("ef.db.update") end,        "EF update database")
  bind(km.ef_db_update_to,     function() require("dotnet.commands.init").run("ef.db.update_to") end,     "EF update database to migration")
  bind(km.ef_db_drop,          function() require("dotnet.commands.init").run("ef.db.drop") end,          "EF drop database")
  bind(km.ef_scaffold,         function() require("dotnet.commands.init").run("ef.scaffold") end,         "EF scaffold DbContext")
  bind(km.debug_launch,    function() require("dotnet.commands.init").run("debug.launch") end,    "Dotnet debug")
  bind(km.launch_settings, function() require("dotnet.commands.init").run("file.launch_settings") end, "Dotnet add launchSettings.json")
  bind(km.run_func,        function() require("dotnet.commands.init").run("run.func") end,        "Azure Function start")
  bind(km.debug_func,      function() require("dotnet.commands.init").run("run.func_debug") end,  "Azure Function debug")
  bind(km.func_new,        function() require("dotnet.commands.init").run("run.func_new") end,      "Azure Function new")

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
