local cmd      = require("dotnet.commands.init")
local solution = require("dotnet.core.solution")
local picker   = require("dotnet.ui.picker")

local function reg(id, def) cmd.register(id, vim.tbl_extend("force", { category = "solution" }, def)) end


reg("solution.remove_project", {
  icon = "󰐘 ",
  desc = "Remove project from solution",
  run  = function()
    picker.project({ prompt = "Remove project:" }, function(proj, sln)
      local name     = vim.fn.fnamemodify(proj, ":t:r")
      local proj_dir = vim.fn.fnamemodify(proj, ":h")
      vim.ui.select({
        "Remove from solution only",
        "Remove from solution and delete from disk",
        "Cancel",
      }, { prompt = "Remove '" .. name .. "'?" }, function(choice)
        if not choice or choice == "Cancel" then return end
        local delete_disk = choice:match("delete from disk")
        solution.remove_project(sln, proj, function()
          if delete_disk then
            vim.fn.delete(proj_dir, "rf")
            require("dotnet.notify").ok("Deleted " .. proj_dir)
          end
        end)
      end)
    end)
  end,
})

reg("solution.add_ref", {
  icon = "󰐒 ",
  desc = "Add project reference",
  run  = function()
    picker.project({ prompt = "Add reference to:" }, function(proj)
      picker.project({ prompt = "Reference project:" }, function(ref)
        if ref == proj then
          require("dotnet.notify").warn("Cannot reference itself")
          return
        end
        require("dotnet.core.project").add_ref(proj, ref, function()
          pcall(function() require("dotnet.ui.explorer").refresh_if_open() end)
        end)
      end)
    end)
  end,
})

reg("solution.remove_ref", {
  icon = "󰐘 ",
  desc = "Remove project reference",
  run  = function()
    picker.project({ prompt = "Remove reference from:" }, function(proj)
      local deps = require("dotnet.core.project").deps(proj)
      local refs = deps.refs or {}
      if #refs == 0 then
        require("dotnet.notify").info("No project references in " .. vim.fn.fnamemodify(proj, ":t:r"))
        return
      end
      vim.ui.select(refs, {
        prompt      = "Remove reference:",
        format_item = function(r) return r.name end,
      }, function(choice)
        if not choice then return end
        local proj_dir = vim.fn.fnamemodify(proj, ":h")
        require("dotnet.core.project").remove(proj_dir, "reference", choice.path, function()
          pcall(function() require("dotnet.ui.explorer").refresh_if_open() end)
        end)
      end)
    end)
  end,
})

reg("solution.new_project", {
  icon = "󰏗 ",
  desc = "New project",
  run  = function()
    -- Templates list; user picks, then provides name + path
    local templates = {
      { value = "webapi",   display = "ASP.NET Core Web API"    },
      { value = "mvc",      display = "ASP.NET Core MVC"        },
      { value = "classlib", display = "Class Library"           },
      { value = "console",  display = "Console Application"     },
      { value = "worker",   display = "Worker Service"          },
      { value = "func",     display = "Azure Functions"         },
      { value = "xunit",    display = "xUnit Test Project"      },
      { value = "nunit",    display = "NUnit Test Project"      },
    }
    vim.ui.select(templates, {
      prompt      = "New project template:",
      format_item = function(t) return t.display end,
    }, function(tpl)
      if not tpl then return end
      vim.ui.input({ prompt = "Project name: " }, function(name)
        if not name or name == "" then return end
        picker.solution(function(sln)
          local sln_dir = vim.fn.fnamemodify(sln, ":h")
          local out = sln_dir .. "/" .. name
          require("dotnet.core.runner").bg(
            { "dotnet", "new", tpl.value, "-o", out, "-n", name },
            { label = "New project " .. name, notify_success = false,
              on_exit = function(code)
                if code ~= 0 then return end
                -- Glob for the csproj — don't assume exact filename (func template varies)
                local found = vim.fn.glob(out .. "/**/*.csproj", false, true)
                if not found or #found == 0 then
                  found = vim.fn.glob(out .. "/*.csproj", false, true)
                end
                if found and #found > 0 then
                  solution.add_project(sln, found[1])
                else
                  require("dotnet.notify").warn("Project created but .csproj not found in " .. out)
                end
              end }
          )
        end)
      end)
    end)
  end,
})
