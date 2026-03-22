-- dotnet.nvim — Migration helpers
-- • Migrate to Central Package Management (Directory.Packages.props)
-- • Add Global Usings (Directory.Build.props)
local cmd      = require("dotnet.commands.init")
local picker   = require("dotnet.ui.picker")
local notify   = require("dotnet.notify")
local solution = require("dotnet.core.solution")

local function reg(id, def) cmd.register(id, vim.tbl_extend("force", { category = "solution" }, def)) end

-- ── Helpers ───────────────────────────────────────────────────────────────────

--- Remove Version attribute from all PackageReference lines in a file.
local function strip_versions(csproj_path)
  local ok, lines = pcall(vim.fn.readfile, csproj_path)
  if not ok then return false end
  local changed = false
  local new_lines = {}
  for _, line in ipairs(lines) do
    local new_line = line:gsub('%s*Version%s*=%s*"[^"]*"', "")
    if new_line ~= line then changed = true end
    table.insert(new_lines, new_line)
  end
  if changed then vim.fn.writefile(new_lines, csproj_path) end
  return changed
end

--- Write Directory.Packages.props and strip versions from all csproj files.
local function migrate_cpm(props, projs, packages)
  local names = vim.tbl_keys(packages)
  table.sort(names)

  local lines = {
    "<Project>",
    "",
    "  <PropertyGroup>",
    "    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>",
    "  </PropertyGroup>",
    "",
    "  <ItemGroup>",
  }
  for _, name in ipairs(names) do
    local p = packages[name]
    if p.attrs ~= "" then
      table.insert(lines, '    <PackageVersion Include="' .. name .. '" Version="' .. p.version .. '">')
      for _, al in ipairs(vim.split(p.attrs, "\n")) do
        table.insert(lines, "    " .. al)
      end
      table.insert(lines, "    </PackageVersion>")
    else
      table.insert(lines, '    <PackageVersion Include="' .. name .. '" Version="' .. p.version .. '" />')
    end
  end
  table.insert(lines, "  </ItemGroup>")
  table.insert(lines, "")
  table.insert(lines, "</Project>")

  vim.fn.writefile(lines, props)

  local stripped = 0
  for _, proj in ipairs(projs) do
    if strip_versions(proj) then stripped = stripped + 1 end
  end

  notify.ok("CPM: " .. #names .. " packages centralized, " .. stripped .. " project(s) updated")
  vim.cmd("edit " .. vim.fn.fnameescape(props))
end

-- ── Central Package Management ─────────────────────────────────────────────────

reg("migrate.cpm", {
  icon = "󰏗 ",
  desc = "Migrate → Central Package Management",
  run  = function()
    picker.solution(function(sln)
      local sln_dir = vim.fn.fnamemodify(sln, ":h")
      local props   = sln_dir .. "/Directory.Packages.props"
      local projs   = solution.projects(sln)

      -- Collect all packages across all projects
      local packages = {}
      for _, proj in ipairs(projs) do
        local ok, lines = pcall(vim.fn.readfile, proj)
        if not ok then goto continue end
        local content = table.concat(lines, "\n")

        -- single-line: Include before Version
        for inc, ver in content:gmatch('<PackageReference%s+Include%s*=%s*"([^"]+)"%s+Version%s*=%s*"([^"]+)"') do
          if not packages[inc] then packages[inc] = { version = ver, attrs = "" } end
        end
        -- single-line: Version before Include
        for ver, inc in content:gmatch('<PackageReference%s+Version%s*=%s*"([^"]+)"%s+Include%s*=%s*"([^"]+)"') do
          if not packages[inc] then packages[inc] = { version = ver, attrs = "" } end
        end
        -- multi-line with child elements (PrivateAssets etc.)
        for attrs, inner in content:gmatch('<PackageReference([^>]+)>(.-)</PackageReference>') do
          local inc = attrs:match('Include%s*=%s*"([^"]+)"')
          local ver = attrs:match('Version%s*=%s*"([^"]+)"')
          if inc and ver and not packages[inc] then
            packages[inc] = { version = ver, attrs = vim.trim(inner) }
          end
        end

        ::continue::
      end

      if vim.tbl_isempty(packages) then
        notify.warn("No versioned PackageReferences found — already migrated?")
        return
      end

      if vim.fn.filereadable(props) == 1 then
        vim.ui.select({ "Overwrite", "Cancel" }, {
          prompt = "Directory.Packages.props already exists:",
        }, function(choice)
          if choice == "Overwrite" then migrate_cpm(props, projs, packages) end
        end)
      else
        migrate_cpm(props, projs, packages)
      end
    end)
  end,
})

-- ── centralisedpackageconverter (community tool) ─────────────────────────────

local CPM_TOOL = "centralisedpackageconverter"

local function cpm_tool_installed()
  local handle = io.popen("dotnet tool list -g 2>/dev/null")
  if not handle then return false end
  local out = handle:read("*a"); handle:close()
  return out:lower():find(CPM_TOOL:lower()) ~= nil
end

reg("migrate.cpm_tool_install", {
  icon = "󰏔 ",
  desc = "Install centralisedpackageconverter (global tool)",
  run  = function()
    if cpm_tool_installed() then
      notify.info(CPM_TOOL .. " already installed")
      return
    end
    require("dotnet.core.runner").bg(
      { "dotnet", "tool", "install", "-g", CPM_TOOL },
      { label = "Installing " .. CPM_TOOL, notify_success = true }
    )
  end,
})

reg("migrate.cpm_tool_run", {
  icon = "󰏗 ",
  desc = "Run centralisedpackageconverter on solution",
  run  = function()
    if not cpm_tool_installed() then
      notify.warn(CPM_TOOL .. " not installed — run 'Install centralisedpackageconverter' first")
      return
    end
    picker.solution(function(sln)
      local sln_dir = vim.fn.fnamemodify(sln, ":h")
      require("dotnet.core.runner").bg(
        { "dotnet", CPM_TOOL, "--solution", sln },
        {
          cwd   = sln_dir,
          label = "CPM convert: " .. vim.fn.fnamemodify(sln, ":t"),
          notify_success = true,
          on_exit = function(code)
            if code == 0 then
              -- Refresh solution explorer so Solution Items picks up new props file
              pcall(function() require("dotnet.ui.explorer").refresh_if_open() end)
            end
          end,
        }
      )
    end)
  end,
})

-- ── Global Usings ──────────────────────────────────────────────────────────────

local COMMON_USINGS = {
  "System",
  "System.Collections.Generic",
  "System.Linq",
  "System.Threading",
  "System.Threading.Tasks",
}

local WEB_USINGS = {
  "Microsoft.AspNetCore.Mvc",
  "Microsoft.Extensions.DependencyInjection",
  "Microsoft.Extensions.Logging",
}

local LIB_USINGS = {
  "Microsoft.Extensions.DependencyInjection",
}

reg("migrate.global_usings", {
  icon = "󰏗 ",
  desc = "Add Global Usings (Directory.Build.props)",
  run  = function()
    picker.solution(function(sln)
      local sln_dir = vim.fn.fnamemodify(sln, ":h")
      local props   = sln_dir .. "/Directory.Build.props"
      local projs   = solution.projects(sln)

      -- Detect project types to pick appropriate usings
      local has_web = false
      for _, proj in ipairs(projs) do
        local ok, lines = pcall(vim.fn.readfile, proj)
        if ok and table.concat(lines, "\n"):match('Sdk="Microsoft%.NET%.Sdk%.Web"') then
          has_web = true; break
        end
      end

      local usings = vim.deepcopy(COMMON_USINGS)
      vim.list_extend(usings, has_web and WEB_USINGS or LIB_USINGS)

      if vim.fn.filereadable(props) == 1 then
        local ok, lines = pcall(vim.fn.readfile, props)
        if ok then
          local existing = table.concat(lines, "\n")
          if existing:match("<Using ") then
            notify.info("Directory.Build.props already has global usings")
            vim.cmd("edit " .. vim.fn.fnameescape(props))
            return
          end
          -- Inject ItemGroup before </Project>
          local block = "  <ItemGroup>\n"
          for _, u in ipairs(usings) do
            block = block .. '    <Using Include="' .. u .. '" />\n'
          end
          block = block .. "  </ItemGroup>\n"
          local new_content = existing:gsub("(</Project>)", block .. "%1")
          vim.fn.writefile(vim.split(new_content, "\n"), props)
        end
      else
        -- Create fresh Directory.Build.props
        local lines = {
          "<Project>",
          "",
          "  <PropertyGroup>",
          "    <TargetFramework>net10.0</TargetFramework>",
          "    <Nullable>enable</Nullable>",
          "    <ImplicitUsings>enable</ImplicitUsings>",
          "  </PropertyGroup>",
          "",
          "  <ItemGroup>",
        }
        for _, u in ipairs(usings) do
          table.insert(lines, '    <Using Include="' .. u .. '" />')
        end
        table.insert(lines, "  </ItemGroup>")
        table.insert(lines, "")
        table.insert(lines, "</Project>")
        vim.fn.writefile(lines, props)
      end

      notify.ok("Global usings added → Directory.Build.props")
      vim.cmd("edit " .. vim.fn.fnameescape(props))
    end)
  end,
})
