local cmd       = require("dotnet.commands.init")
local namespace = require("dotnet.core.namespace")
local solution  = require("dotnet.core.solution")
local project   = require("dotnet.core.project")
local picker    = require("dotnet.ui.picker")

local function reg(id, def) cmd.register(id, vim.tbl_extend("force", { category = "file" }, def)) end

local TEMPLATES = {
  { value = "class",          display = "Class",                   ext = ".cs"     },
  { value = "interface",      display = "Interface",               ext = ".cs"     },
  { value = "record",         display = "Record",                  ext = ".cs"     },
  { value = "struct",         display = "Struct",                  ext = ".cs"     },
  { value = "enum",           display = "Enum",                    ext = ".cs"     },
  { value = "apicontroller",  display = "API Controller",          ext = ".cs"     },
  { value = "mvccontroller",  display = "MVC Controller",          ext = ".cs"     },
  { value = "razorcomponent", display = "Razor Component",         ext = ".razor"  },
  { value = "page",           display = "Razor Page",              ext = ".cshtml" },
  { value = "view",           display = "Razor View",              ext = ".cshtml" },
  { value = "nunit-test",     display = "NUnit Test",              ext = ".cs"     },
  { value = "buildprops",     display = "Directory.Build.props",   predefined = "Directory.Build.props"    },
  { value = "packagesprops",  display = "Directory.Packages.props",predefined = "Directory.Packages.props" },
  { value = "gitignore",      display = ".gitignore",              predefined = ".gitignore"   },
  { value = "editorconfig",   display = ".editorconfig",           predefined = ".editorconfig" },
  { value = "globaljson",     display = "global.json",             predefined = "global.json"  },
  { value = "nugetconfig",    display = "nuget.config",            predefined = "nuget.config" },
}

local function do_new_item(proj_path, target_dir)
  local proj_dir = vim.fn.fnamemodify(proj_path, ":h")
  local out_dir  = target_dir or proj_dir

  vim.ui.select(TEMPLATES, {
    prompt      = "New item (" .. vim.fn.fnamemodify(proj_path, ":t:r") .. "):",
    format_item = function(t) return t.display end,
  }, function(tpl)
    if not tpl then return end

    local function run(name)
      local dest_abs, o_flag, file_path
      if tpl.predefined then
        dest_abs  = out_dir
        o_flag    = out_dir
        file_path = out_dir .. "/" .. tpl.predefined
      else
        local sub  = name:match("^(.+)/[^/]+$")
        local base = name:match("([^/]+)$")
        dest_abs   = sub and (out_dir .. "/" .. sub) or out_dir
        vim.fn.mkdir(dest_abs, "p")
        local rel  = dest_abs:sub(#proj_dir + 2)
        o_flag     = rel ~= "" and rel or "."
        file_path  = dest_abs .. "/" .. base .. tpl.ext
        name       = base
      end

      local args = tpl.predefined
        and { "dotnet", "new", tpl.value, "-o", o_flag }
        or  { "dotnet", "new", tpl.value, "-o", o_flag, "-n", name }

      require("dotnet.core.runner").bg(args, {
        cwd   = proj_dir,
        label = "New " .. (tpl.label or name),
        notify_success = false,
        on_exit = function(code)
          if code ~= 0 then return end
          if tpl.ext == ".cs" and vim.fn.filereadable(file_path) == 1 then
            local ns = namespace.compute(proj_path, file_path)
            namespace.patch_file(file_path, ns)
          end
          if vim.fn.filereadable(file_path) == 1 then
            vim.cmd("edit " .. vim.fn.fnameescape(file_path))
          end
        end,
      })
    end

    if tpl.predefined then
      run(nil)
    else
      vim.ui.input({ prompt = "Name (e.g. MyClass or Sub/MyClass): " }, function(name)
        if name and name ~= "" then run(name) end
      end)
    end
  end)
end

reg("file.new_item", {
  icon = "󰝒 ",
  desc = "New item (class, interface, etc.)",
  run  = function()
    picker.project({ prompt = "New item in project:" }, function(proj)
      do_new_item(proj)
    end)
  end,
})

reg("file.fix_namespace", {
  icon = "󰏫 ",
  desc = "Fix namespace of current file",
  run  = function()
    local file_path = vim.api.nvim_buf_get_name(0)
    if not file_path:match("%.cs$") then
      require("dotnet.notify").warn("Not a .cs file")
      return
    end
    local sln = solution.find()
    if not sln then return end
    local projs = solution.projects(sln)
    local proj  = project.owner(file_path, projs)
    if not proj then
      require("dotnet.notify").warn("File not in any project")
      return
    end
    local ns = namespace.compute(proj, file_path)
    if namespace.patch_buf(0, ns) then
      require("dotnet.notify").info("Namespace → " .. ns)
    else
      require("dotnet.notify").warn("No namespace declaration found")
    end
  end,
})

reg("file.launch_settings", {
  icon = " ",
  desc = "Add launchSettings.json",
  run  = function()
    picker.runnable({ prompt = "Add launchSettings.json to:" }, function(csproj)
      if not csproj then return end

      local project_dir = vim.fn.fnamemodify(csproj, ":h")
      local props_dir   = project_dir .. "/Properties"
      local target       = props_dir .. "/launchSettings.json"

      if vim.fn.filereadable(target) == 1 then
        require("dotnet.notify").info("launchSettings.json already exists — opening it.")
        vim.cmd("edit " .. vim.fn.fnameescape(target))
        return
      end

      vim.fn.mkdir(props_dir, "p")

      local template = [[{
  "$schema": "https://json.schemastore.org/launchsettings.json",
  "profiles": {
    "http": {
      "commandName": "Project",
      "dotnetRunMessages": true,
      "launchBrowser": false,
      "applicationUrl": "http://localhost:5131",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      }
    },
    "https": {
      "commandName": "Project",
      "dotnetRunMessages": true,
      "launchBrowser": false,
      "applicationUrl": "https://localhost:7165;http://localhost:5131",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      }
    }
  }
}
]]

      local f = io.open(target, "w")
      if not f then
        require("dotnet.notify").error("Failed to write " .. target)
        return
      end
      f:write(template)
      f:close()

      require("dotnet.notify").info("Created " .. target)
      vim.cmd("edit " .. vim.fn.fnameescape(target))
    end)
  end,
})

-- Expose do_new_item for solution explorer to call directly with context
M = require("dotnet.commands.init")
M.new_item = do_new_item
