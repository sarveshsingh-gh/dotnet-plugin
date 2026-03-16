local cmd    = require("dotnet.commands.init")
local runner = require("dotnet.core.runner")
local picker = require("dotnet.ui.picker")

local function reg(id, def) cmd.register(id, vim.tbl_extend("force", { category = "test" }, def)) end

reg("test.solution", {
  icon = "󰙨 ",
  desc = "Test solution",
  run  = function()
    picker.solution(function(sln)
      runner.test(sln)
    end)
  end,
})

reg("test.project", {
  icon = "󰙨 ",
  desc = "Test project",
  run  = function()
    picker.project({ prompt = "Test project:" }, function(proj)
      runner.test(proj)
    end)
  end,
})

reg("test.solution_qf", {
  icon = "󰙨 ",
  desc = "Test solution → Quickfix",
  run  = function()
    picker.solution(function(sln)
      runner.test_qf(sln)
    end)
  end,
})

reg("test.project_qf", {
  icon = "󰙨 ",
  desc = "Test project → Quickfix",
  run  = function()
    picker.project({ prompt = "Test project (quickfix):" }, function(proj)
      runner.test_qf(proj)
    end)
  end,
})
