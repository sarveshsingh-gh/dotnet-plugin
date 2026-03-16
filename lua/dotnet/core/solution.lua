-- Parse and manage .sln / .slnx solution files.
local M = {}

--- Find the first .slnx or .sln in dir (default: cwd).
function M.find(dir)
  dir = dir or vim.fn.getcwd()
  for _, pat in ipairs({ "*.slnx", "*.sln" }) do
    local hits = vim.fn.glob(dir .. "/" .. pat, false, true)
    if #hits > 0 then return hits[1] end
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

--- Add a project to the solution (runs dotnet sln add).
function M.add_project(sln_path, proj_path, cb)
  require("dotnet.core.runner").bg(
    { "dotnet", "sln", sln_path, "add", proj_path },
    { label = "Add project to solution", on_exit = function(code) if code == 0 and cb then cb() end end }
  )
end

--- Remove a project from the solution (runs dotnet sln remove).
function M.remove_project(sln_path, proj_path, cb)
  require("dotnet.core.runner").bg(
    { "dotnet", "sln", sln_path, "remove", proj_path },
    { label = "Remove project from solution", on_exit = function(code) if code == 0 and cb then cb() end end }
  )
end

return M
