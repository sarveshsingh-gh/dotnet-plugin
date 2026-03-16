-- Reusable project / solution pickers used by commands.
local M = {}

local solution = require("dotnet.core.solution")
local project  = require("dotnet.core.project")

--- Pick a solution (finds automatically, or lets user pick if multiple exist).
-- cb(sln_path)
function M.solution(cb)
  local sln = solution.find()
  if sln then return cb(sln) end
  vim.notify("[dotnet] No .sln/.slnx found in cwd", vim.log.levels.WARN)
end

--- Pick a project from the solution.
-- opts: { filter }  — optional filter fn(proj_path) → bool
-- cb(proj_path, sln_path)
function M.project(opts, cb)
  if type(opts) == "function" then cb = opts; opts = {} end
  M.solution(function(sln)
    local all   = solution.projects(sln)
    local projs = opts.filter and vim.tbl_filter(opts.filter, all) or all
    if #projs == 0 then
      vim.notify("[dotnet] No matching projects found", vim.log.levels.WARN)
      return
    end
    if #projs == 1 then return cb(projs[1], sln) end
    vim.ui.select(projs, {
      prompt      = opts.prompt or "Select project:",
      format_item = function(p) return vim.fn.fnamemodify(p, ":t:r") end,
    }, function(p)
      if p then cb(p, sln) end
    end)
  end)
end

--- Pick a runnable project (web or console).
function M.runnable(opts, cb)
  if type(opts) == "function" then cb = opts; opts = {} end
  opts.filter = project.runnable
  opts.prompt = opts.prompt or "Select runnable project:"
  M.project(opts, cb)
end

--- Pick any project (solution-level target = the .sln itself) or a specific project.
-- Shows: [Solution], then each project.
-- cb(target, kind)  — kind: "solution" | "project"
function M.target(opts, cb)
  if type(opts) == "function" then cb = opts; opts = {} end
  M.solution(function(sln)
    local projs = solution.projects(sln)
    local items = {}
    table.insert(items, { label = "⬡ " .. vim.fn.fnamemodify(sln, ":t"), path = sln, kind = "solution" })
    for _, p in ipairs(projs) do
      table.insert(items, { label = "  " .. vim.fn.fnamemodify(p, ":t:r"), path = p, kind = "project" })
    end
    vim.ui.select(items, {
      prompt      = opts.prompt or "Select target:",
      format_item = function(i) return i.label end,
    }, function(item)
      if item then cb(item.path, item.kind, sln) end
    end)
  end)
end

--- Pick a launch profile for a project (from launchSettings.json).
-- cb(profile_name or nil)
function M.launch_profile(proj_path, cb)
  local settings_path = vim.fn.fnamemodify(proj_path, ":h")
    .. "/Properties/launchSettings.json"
  local ok, raw = pcall(vim.fn.readfile, settings_path)
  if not ok then return cb(nil) end
  local json_ok, data = pcall(vim.fn.json_decode, table.concat(raw, ""))
  if not json_ok or not data or not data.profiles then return cb(nil) end
  local profiles = vim.tbl_keys(data.profiles)
  if #profiles == 0 then return cb(nil) end
  if #profiles == 1 then return cb(profiles[1]) end
  vim.ui.select(profiles, { prompt = "Select launch profile:" }, function(p)
    cb(p)
  end)
end

return M
