-- Parse .csproj / .fsproj files.
local M = {}

local ALWAYS_SKIP = { [".vs"]=true, [".git"]=true }
local BUILD_DIRS  = { bin=true, obj=true }
local SKIP_EXTS   = { dll=true, pdb=true, exe=true, nupkg=true, cache=true, user=true, suo=true }

--- Read basic properties from a project file.
-- Returns { root_namespace, target_framework, output_type, sdk }
function M.properties(proj_path)
  local ok, lines = pcall(vim.fn.readfile, proj_path)
  if not ok then return {} end
  local content = table.concat(lines, "\n")
  return {
    root_namespace   = content:match("<RootNamespace>([^<]+)</RootNamespace>"),
    target_framework = content:match("<TargetFramework>([^<]+)</TargetFramework>"),
    output_type      = content:match("<OutputType>([^<]+)</OutputType>"),
    sdk              = content:match('Sdk="([^"]+)"') or content:match("Sdk='([^']+)'"),
  }
end

--- Return { pkgs = [{name,version}], refs = [{name,path}] }
function M.deps(proj_path)
  local result = { pkgs = {}, refs = {} }
  local ok, lines = pcall(vim.fn.readfile, proj_path)
  if not ok then return result end
  local proj_dir = vim.fn.fnamemodify(proj_path, ":h")

  for _, line in ipairs(lines) do
    local pkg = line:match('<PackageReference[^>]+Include="([^"]+)"')
    if pkg then
      local ver = line:match('Version="([^"]+)"') or ""
      table.insert(result.pkgs, { name = pkg, version = ver })
    end
    local ref = line:match('<ProjectReference[^>]+Include="([^"]+)"')
    if ref then
      local rp   = vim.fn.fnamemodify(proj_dir .. "/" .. ref:gsub("\\", "/"), ":p")
      local name = vim.fn.fnamemodify(rp, ":t:r")
      table.insert(result.refs, { name = name, path = rp })
    end
  end
  return result
end

--- Detect project kind from properties.
-- Returns "web" | "console" | "test" | "lib"
function M.kind(proj_path)
  local ok, lines = pcall(vim.fn.readfile, proj_path)
  if not ok then return "lib" end
  local content = table.concat(lines, "\n")
  local name    = vim.fn.fnamemodify(proj_path, ":t:r"):lower()

  if name:match("test") or name:match("spec")
     or content:match("xunit") or content:match("nunit") or content:match("mstest")
     or content:match("Microsoft%.NET%.Test%.Sdk") then
    return "test"
  end
  if content:match('Sdk="Microsoft%.NET%.Sdk%.Web"') or content:match("Sdk='Microsoft%.NET%.Sdk%.Web'") then
    return "web"
  end
  if content:match("<OutputType>Exe</OutputType>") then return "console" end
  return "lib"
end

--- True if the project can be run (web or console).
function M.runnable(proj_path)
  local k = M.kind(proj_path)
  return k == "web" or k == "console"
end

--- Recursively scan a project directory for source files.
-- Returns list of { name, path, is_dir, depth }
function M.scan_dir(dir, show_hidden)
  local result = {}
  local function scan(d, depth)
    if depth > 8 then return end
    local ok, entries = pcall(vim.fn.readdir, d)
    if not ok then return end
    table.sort(entries, function(a, b)
      local ad = vim.fn.isdirectory(d .. "/" .. a) == 1
      local bd = vim.fn.isdirectory(d .. "/" .. b) == 1
      if ad ~= bd then return ad end
      return a:lower() < b:lower()
    end)
    for _, name in ipairs(entries) do
      local full   = d .. "/" .. name
      local is_dir = vim.fn.isdirectory(full) == 1
      if is_dir then
        local skip = ALWAYS_SKIP[name] or (not show_hidden and BUILD_DIRS[name])
        if not skip then
          table.insert(result, { name=name, path=full, is_dir=true,  depth=depth })
          scan(full, depth + 1)
        end
      else
        local ext = name:match("%.([^.]+)$") or ""
        if not SKIP_EXTS[ext] then
          table.insert(result, { name=name, path=full, is_dir=false, depth=depth })
        end
      end
    end
  end
  scan(dir, 0)
  return result
end

--- Find which project (from proj_paths) owns file_path.
-- Returns the .csproj path or nil.
function M.owner(file_path, proj_paths)
  for _, pp in ipairs(proj_paths) do
    local pd = vim.fn.fnamemodify(pp, ":h")
    if file_path:sub(1, #pd + 1) == pd .. "/" then return pp end
  end
end

--- Add a project reference.
function M.add_ref(proj_path, ref_path, cb)
  local stderr = {}
  vim.fn.jobstart({ "dotnet", "add", proj_path, "reference", ref_path }, {
    on_stderr = function(_, d) for _, l in ipairs(d) do if l ~= "" then table.insert(stderr, l) end end end,
    on_exit   = function(_, code)
      vim.schedule(function()
        if code ~= 0 then
          vim.notify("[dotnet] add reference failed:\n" .. table.concat(stderr, "\n"), vim.log.levels.ERROR)
        else
          vim.notify("[dotnet] Reference added", vim.log.levels.INFO)
          if cb then cb() end
        end
      end)
    end,
  })
end

--- Remove a package or project reference (cwd = project dir).
function M.remove(proj_dir, kind, name_or_path, cb)
  -- kind: "package" | "reference"
  local stderr = {}
  vim.fn.jobstart({ "dotnet", "remove", kind, name_or_path }, {
    cwd       = proj_dir,
    on_stderr = function(_, d) for _, l in ipairs(d) do if l ~= "" then table.insert(stderr, l) end end end,
    on_exit   = function(_, code)
      vim.schedule(function()
        if code ~= 0 then
          vim.notify("[dotnet] remove failed:\n" .. table.concat(stderr, "\n"), vim.log.levels.ERROR)
        else
          vim.notify("[dotnet] Removed " .. name_or_path, vim.log.levels.INFO)
          if cb then cb() end
        end
      end)
    end,
  })
end

return M
