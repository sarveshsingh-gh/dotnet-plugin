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
          local out     = sln_dir .. "/" .. name
          local stderr  = {}
          vim.fn.jobstart({ "dotnet", "new", tpl.value, "-o", out, "-n", name }, {
            on_stderr = function(_, d) for _, l in ipairs(d) do if l ~= "" then table.insert(stderr, l) end end end,
            on_exit   = function(_, code)
              vim.schedule(function()
                if code ~= 0 then
                  vim.notify("[dotnet] new project failed:\n" .. table.concat(stderr, "\n"), vim.log.levels.ERROR)
                  return
                end
                local proj_file = out .. "/" .. name .. ".csproj"
                if vim.fn.filereadable(proj_file) == 1 then
                  solution.add_project(sln, proj_file, function()
                    vim.notify("[dotnet] Created and added: " .. name, vim.log.levels.INFO)
                  end)
                end
              end)
            end,
          })
        end)
      end)
    end)
  end,
})
