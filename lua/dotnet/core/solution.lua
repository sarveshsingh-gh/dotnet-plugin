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
  local stderr = {}
  vim.fn.jobstart({ "dotnet", "sln", sln_path, "add", proj_path }, {
    on_stderr = function(_, d) for _, l in ipairs(d) do if l ~= "" then table.insert(stderr, l) end end end,
    on_exit   = function(_, code)
      vim.schedule(function()
        if code ~= 0 then
          vim.notify("[dotnet] sln add failed:\n" .. table.concat(stderr, "\n"), vim.log.levels.ERROR)
        else
          vim.notify("[dotnet] Project added to solution", vim.log.levels.INFO)
          if cb then cb() end
        end
      end)
    end,
  })
end

--- Remove a project from the solution (runs dotnet sln remove).
function M.remove_project(sln_path, proj_path, cb)
  local stderr = {}
  vim.fn.jobstart({ "dotnet", "sln", sln_path, "remove", proj_path }, {
    on_stderr = function(_, d) for _, l in ipairs(d) do if l ~= "" then table.insert(stderr, l) end end end,
    on_exit   = function(_, code)
      vim.schedule(function()
        if code ~= 0 then
          vim.notify("[dotnet] sln remove failed:\n" .. table.concat(stderr, "\n"), vim.log.levels.ERROR)
        else
          vim.notify("[dotnet] Project removed from solution", vim.log.levels.INFO)
          if cb then cb() end
        end
      end)
    end,
  })
end

return M
