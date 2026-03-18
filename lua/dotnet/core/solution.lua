-- Parse and manage .sln / .slnx solution files.
local M = {}

--- Find the first .slnx or .sln, walking up from dir (default: cwd).
function M.find(dir)
  local d = vim.fn.fnamemodify(dir or vim.fn.getcwd(), ":p")
  -- strip trailing slash
  d = d:gsub("/$", "")
  while d ~= "" do
    for _, pat in ipairs({ "*.slnx", "*.sln" }) do
      local hits = vim.fn.glob(d .. "/" .. pat, false, true)
      if #hits > 0 then return hits[1] end
    end
    local parent = vim.fn.fnamemodify(d, ":h")
    if parent == d then break end
    d = parent
  end
end

--- Return list of absolute .csproj / .fsproj paths from a solution file.
function M.projects(sln_path)
  local lines = vim.fn.readfile(sln_path)
  local dir   = vim.fn.fnamemodify(sln_path, ":h")
  local paths = {}

  if sln_path:match("%.slnx$") then
    for _, l in ipairs(lines) do
      local rel = l:match('Path="([^"]+%.c?f?sproj)"')
      if rel then
        table.insert(paths, vim.fn.fnamemodify(dir .. "/" .. rel:gsub("\\", "/"), ":p"))
      end
    end
  else
    for _, l in ipairs(lines) do
      local rel = l:match('"([^"]+%.c?f?sproj)"')
      if rel then
        table.insert(paths, vim.fn.fnamemodify(dir .. "/" .. rel:gsub("\\", "/"), ":p"))
      end
    end
  end

  return vim.tbl_filter(function(p) return vim.fn.filereadable(p) == 1 end, paths)
end

local function explorer_refresh()
  local ok, exp = pcall(require, "dotnet.ui.explorer")
  if ok then pcall(exp.refresh_if_open) end
end

--- Add a project to the solution (runs dotnet sln add).
function M.add_project(sln_path, proj_path, cb)
  local name = vim.fn.fnamemodify(proj_path, ":t:r")
  require("dotnet.core.runner").bg(
    { "dotnet", "sln", sln_path, "add", proj_path },
    { label = "Adding " .. name .. " to solution", on_exit = function(code)
        if code == 0 then
          explorer_refresh()
          if cb then cb() end
        end
      end }
  )
end

--- Remove a project from the solution (runs dotnet sln remove).
function M.remove_project(sln_path, proj_path, cb)
  local name = vim.fn.fnamemodify(proj_path, ":t:r")
  require("dotnet.core.runner").bg(
    { "dotnet", "sln", sln_path, "remove", proj_path },
    { label = "Removing " .. name .. " from solution", on_exit = function(code)
        if code == 0 then
          explorer_refresh()
          if cb then cb() end
        end
      end }
  )
end

return M
