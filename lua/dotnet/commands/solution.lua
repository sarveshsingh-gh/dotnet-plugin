local cmd      = require("dotnet.commands.init")
local solution = require("dotnet.core.solution")
local picker   = require("dotnet.ui.picker")

local function reg(id, def) cmd.register(id, vim.tbl_extend("force", { category = "solution" }, def)) end

reg("solution.add_project", {
  icon = " ",
  desc = "Add project to solution",
  run  = function()
    picker.solution(function(sln)
      vim.ui.input({ prompt = "Project path (.csproj): " }, function(path)
        if path and path ~= "" then
          solution.add_project(sln, vim.fn.fnamemodify(path, ":p"))
        end
      end)
    end)
  end,
})

reg("solution.remove_project", {
  icon = " ",
  desc = "Remove project from solution",
  run  = function()
    picker.project({ prompt = "Remove project:" }, function(proj, sln)
      vim.ui.input({ prompt = "Confirm remove '" .. vim.fn.fnamemodify(proj, ":t:r") .. "'? [y/N]: " },
        function(ans)
          if ans and ans:lower() == "y" then
            solution.remove_project(sln, proj)
          end
        end)
    end)
  end,
})

reg("solution.new_project", {
  icon = " ",
  desc = "New project",
  run  = function()
    -- Templates list; user picks, then provides name + path
    local templates = {
      { value = "webapi",   display = "ASP.NET Core Web API"    },
      { value = "mvc",      display = "ASP.NET Core MVC"        },
      { value = "classlib", display = "Class Library"           },
      { value = "console",  display = "Console Application"     },
      { value = "worker",   display = "Worker Service"          },
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
                local proj_file = out .. "/" .. name .. ".csproj"
                if vim.fn.filereadable(proj_file) == 1 then
                  solution.add_project(sln, proj_file)
                end
              end }
          )
        end)
      end)
    end)
  end,
})
