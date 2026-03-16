local cmd    = require("dotnet.commands.init")
local runner = require("dotnet.core.runner")
local picker = require("dotnet.ui.picker")

local function reg(id, def) cmd.register(id, vim.tbl_extend("force", { category = "run" }, def)) end

reg("run.project", {
  icon = "󰐊 ",
  desc = "Run project",
  run  = function()
    picker.runnable({ prompt = "Run project:" }, function(proj)
      runner.run(proj)
    end)
  end,
})

reg("run.profile", {
  icon = "󰐊 ",
  desc = "Run project with launch profile",
  run  = function()
    picker.runnable({ prompt = "Run project (profile):" }, function(proj)
      picker.launch_profile(proj, function(profile)
        runner.run(proj, { profile = profile })
      end)
    end)
  end,
})

reg("run.watch", {
  icon = "󰑓 ",
  desc = "Watch (hot-reload)",
  run  = function()
    picker.runnable({ prompt = "Watch project:" }, function(proj)
      runner.watch(proj)
    end)
  end,
})

reg("run.stop_all", {
  icon = "󰓛 ",
  desc = "Stop all running processes",
  run  = runner.stop_all,
})
