-- Reusable project / solution pickers used by commands.
local M = {}

local solution = require("dotnet.core.solution")
local project  = require("dotnet.core.project")

--- Pick a solution (finds automatically, or lets user pick if multiple exist).
-- cb(sln_path)
function M.solution(cb)
  -- 1. Use cached sln from startup
  local sln = require("dotnet").sln()
  -- 2. Walk up from current buffer's directory
  if not sln then
    local bufdir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":h")
    if bufdir ~= "" and bufdir ~= "." then sln = solution.find(bufdir) end
  end
  -- 3. Walk up from cwd
  if not sln then sln = solution.find() end
  if sln then return cb(sln) end
  require("dotnet.notify").warn("No .sln/.slnx found")
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
      require("dotnet.notify").warn("No matching projects found")
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

--- Find the project that owns the current buffer's file.
-- Returns proj_path or nil.
function M.project_for_current_file(sln)
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then return nil end
  local projs = solution.projects(sln)
  -- longest matching project dir wins
  local best, best_len = nil, 0
  for _, p in ipairs(projs) do
    local dir = vim.fn.fnamemodify(p, ":h") .. "/"
    if file:sub(1, #dir) == dir and #dir > best_len then
      best, best_len = p, #dir
    end
  end
  return best
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
