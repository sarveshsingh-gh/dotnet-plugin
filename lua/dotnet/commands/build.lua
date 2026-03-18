local cmd    = require("dotnet.commands.init")
local runner = require("dotnet.core.runner")
local picker = require("dotnet.ui.picker")

local function reg(id, def) cmd.register(id, vim.tbl_extend("force", { category = "build" }, def)) end

reg("build.solution", {
  icon = "󰘗 ",
  desc = "Build solution",
  run  = function()
    picker.target({ prompt = "Build target:" }, function(target)
      runner.build(target)
    end)
  end,
})

reg("build.quickfix", {
  icon = "󰘗 ",
  desc = "Build → Quickfix (errors in qf list)",
  run  = function()
    picker.target({ prompt = "Build target (quickfix):" }, function(target)
      runner.build_qf(target)
    end)
  end,
})

reg("build.restore", {
  icon = "󰑓 ",
  desc = "Restore packages",
  run  = function()
    picker.target({ prompt = "Restore target:" }, function(target)
      runner.restore(target)
    end)
  end,
})

reg("build.clean", {
  icon = "󰃢 ",
  desc = "Clean",
  run  = function()
    picker.target({ prompt = "Clean target:" }, function(target)
      runner.clean(target)
    end)
  end,
})

reg("build.rebuild", {
  icon = "󰑐 ",
  desc = "Rebuild (clean + build)",
  run  = function()
    picker.target({ prompt = "Rebuild target:" }, function(target, _, sln)
      runner.clean(target, {
        notify_success = false,
        on_exit = function(code)
          if code == 0 then runner.build(target) end
        end,
      })
    end)
  end,
})
