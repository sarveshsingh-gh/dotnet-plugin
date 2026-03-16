-- dotnet.nvim — NuGet commands
local cmd    = require("dotnet.commands.init")
local runner = require("dotnet.core.runner")
local picker = require("dotnet.ui.picker")

-- Search NuGet.org via the nuget search API (no auth required)
local function search_packages(query, cb)
  local url = "https://azuresearch-usnc.nuget.org/query?q="
    .. vim.uri_encode(query) .. "&take=50&prerelease=false"

  local buf = {}
  vim.fn.jobstart({ "curl", "-sf", url }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then table.insert(buf, line) end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.notify("[dotnet] NuGet search failed", vim.log.levels.WARN)
        return cb({})
      end
      local ok, decoded = pcall(vim.json.decode, table.concat(buf))
      if not ok or not decoded or not decoded.data then
        return cb({})
      end
      local results = {}
      for _, pkg in ipairs(decoded.data) do
        table.insert(results, {
          id      = pkg.id,
          version = pkg.version,
          desc    = pkg.description or "",
          total   = pkg.totalDownloads or 0,
        })
      end
      cb(results)
    end,
  })
end

local function do_add_package(proj_path)
  vim.ui.input({ prompt = "Search NuGet: " }, function(query)
    if not query or query == "" then return end
    vim.notify("[dotnet] Searching NuGet for: " .. query, vim.log.levels.INFO)
    search_packages(query, function(results)
      if #results == 0 then
        vim.notify("[dotnet] No packages found", vim.log.levels.WARN)
        return
      end
      local items = vim.tbl_map(function(p)
        return string.format("%-40s  %s", p.id, p.version)
      end, results)

      vim.schedule(function()
        vim.ui.select(items, { prompt = "Select package:" }, function(choice, idx)
          if not choice then return end
          local pkg = results[idx]
          runner.bg({ "dotnet", "add", "package", pkg.id, "--version", pkg.version }, {
            cwd   = vim.fn.fnamemodify(proj_path, ":h"),
            label = "NuGet add " .. pkg.id,
            notify = true,
          })
        end)
      end)
    end)
  end)
end

local function do_remove_package(proj_path)
  -- Read current packages from csproj
  local ok, props = pcall(require("dotnet.core.project").deps, proj_path)
  local pkgs = (ok and props and props.pkgs) or {}
  if #pkgs == 0 then
    vim.notify("[dotnet] No packages found in project", vim.log.levels.INFO)
    return
  end
  vim.ui.select(pkgs, { prompt = "Remove package:" }, function(choice)
    if not choice then return end
    runner.bg({ "dotnet", "remove", "package", choice }, {
      cwd   = vim.fn.fnamemodify(proj_path, ":h"),
      label = "NuGet remove " .. choice,
      notify = true,
    })
  end)
end

local function do_list_packages(proj_path)
  local cwd = vim.fn.fnamemodify(proj_path, ":h")
  runner.bg({ "dotnet", "list", "package" }, {
    cwd   = cwd,
    label = "NuGet list",
    on_exit = function(lines)
      local result = {}
      for _, l in ipairs(lines) do
        if l:match("^%s*>") then
          table.insert(result, vim.trim(l))
        end
      end
      if #result == 0 then
        vim.notify("[dotnet] No packages", vim.log.levels.INFO)
      else
        vim.schedule(function()
          vim.notify("[dotnet] Packages:\n" .. table.concat(result, "\n"), vim.log.levels.INFO)
        end)
      end
    end,
  })
end

local function do_outdated(proj_path)
  local cwd = vim.fn.fnamemodify(proj_path, ":h")
  runner.bg({ "dotnet", "list", "package", "--outdated" }, {
    cwd   = cwd,
    label = "NuGet outdated",
    on_exit = function(lines)
      local result = {}
      for _, l in ipairs(lines) do
        if l:match("^%s*>") then
          table.insert(result, vim.trim(l))
        end
      end
      if #result == 0 then
        vim.notify("[dotnet] All packages up to date", vim.log.levels.INFO)
      else
        vim.schedule(function()
          local msg = table.concat(result, "\n")
          vim.notify("[dotnet] Outdated packages:\n" .. msg, vim.log.levels.WARN)
        end)
      end
    end,
  })
end

-- Register commands
cmd.register("nuget.add", {
  category = "nuget",
  icon     = " ",
  desc     = "Add NuGet package",
  run      = function()
    picker.project({}, function(proj)
      do_add_package(proj)
    end)
  end,
})

cmd.register("nuget.remove", {
  category = "nuget",
  icon     = " ",
  desc     = "Remove NuGet package",
  run      = function()
    picker.project({}, function(proj)
      do_remove_package(proj)
    end)
  end,
})

cmd.register("nuget.list", {
  category = "nuget",
  icon     = "󰒕 ",
  desc     = "List NuGet packages",
  run      = function()
    picker.project({}, function(proj)
      do_list_packages(proj)
    end)
  end,
})

cmd.register("nuget.outdated", {
  category = "nuget",
  icon     = "󰏗 ",
  desc     = "List outdated packages",
  run      = function()
    picker.project({}, function(proj)
      do_outdated(proj)
    end)
  end,
})

local M = {}
M.add_package     = do_add_package
M.remove_package  = do_remove_package
M.list_packages   = do_list_packages
M.outdated        = do_outdated
return M
