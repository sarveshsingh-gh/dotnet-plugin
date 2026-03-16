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
    -- Auto-detect from current buffer; fall back to picker
    local file = vim.api.nvim_buf_get_name(0)
    local sln  = require("dotnet").sln()
    if sln and file ~= "" then
      for _, p in ipairs(require("dotnet.core.solution").projects(sln)) do
        local dir = vim.fn.fnamemodify(p, ":h") .. "/"
        if file:sub(1, #dir) == dir then
          runner.test(p)
          return
        end
      end
    end
    picker.project({ prompt = "Test project:" }, function(p) runner.test(p) end)
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
