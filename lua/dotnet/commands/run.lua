local cmd    = require("dotnet.commands.init")
local runner = require("dotnet.core.runner")
local picker = require("dotnet.ui.picker")

local function reg(id, def) cmd.register(id, vim.tbl_extend("force", { category = "run" }, def)) end

reg("run.project", {
  icon = "󰐊 ",
  desc = "Run project",
  run  = function()
    picker.runnable({ prompt = "Run project:" }, function(proj)
      runner.run(proj)
    end)
  end,
})

reg("run.profile", {
  icon = "󰐊 ",
  desc = "Run project with launch profile",
  run  = function()
    picker.runnable({ prompt = "Run project (profile):" }, function(proj)
      picker.launch_profile(proj, function(profile)
        runner.run(proj, { profile = profile })
      end)
    end)
  end,
})

reg("run.watch", {
  icon = "󰑓 ",
  desc = "Watch (hot-reload)",
  run  = function()
    picker.runnable({ prompt = "Watch project:" }, function(proj)
      runner.watch(proj)
    end)
  end,
})

reg("run.stop_all", {
  icon = "󰓛 ",
  desc = "Stop all running processes",
  run  = runner.stop_all,
})

reg("run.func", {
  icon = "󰡱 ",
  desc = "Start Azure Function (func start)",
  run  = function()
    if vim.fn.executable("func") == 0 then
      require("dotnet.notify").warn("Azure Functions Core Tools ('func') not found in PATH")
      return
    end
    picker.runnable({ prompt = "Start Azure Function:" }, function(proj)
      local proj_dir = vim.fn.fnamemodify(proj, ":h")
      runner.term({ "func", "start" }, {
        cwd   = proj_dir,
        label = "func start — " .. vim.fn.fnamemodify(proj, ":t:r"),
      })
    end)
  end,
})

reg("run.func_debug", {
  icon = "󰡱 ",
  desc = "Debug Azure Function (func start + attach)",
  run  = function()
    if vim.fn.executable("func") == 0 then
      require("dotnet.notify").warn("Azure Functions Core Tools ('func') not found in PATH")
      return
    end
    picker.runnable({ prompt = "Debug Azure Function:" }, function(proj)
      local proj_dir = vim.fn.fnamemodify(proj, ":h")
      local name     = vim.fn.fnamemodify(proj, ":t:r")
      local notify   = require("dotnet.notify")
      local ok, dap  = pcall(require, "dap")
      if not ok then notify.warn("nvim-dap not available"); return end

      local spin    = notify.start_spinner("Starting func host for " .. name .. "…")
      local attached = false

      vim.fn.jobstart({ "func", "start", "--language-worker-port", "5858" }, {
        cwd             = proj_dir,
        stdout_buffered = false,
        on_stdout = function(_, data)
          for _, line in ipairs(data or {}) do
            -- func host prints "Host lock lease acquired" when ready
            if not attached and line:match("Host lock lease acquired") then
              attached = true
              vim.schedule(function()
                notify.stop_spinner(spin)
                notify.info("func host ready — attaching debugger")
                dap.run({
                  type      = "coreclr",
                  name      = "Debug Azure Function: " .. name,
                  request   = "attach",
                  processId = require("dap.utils").pick_process,
                })
              end)
            end
          end
        end,
        on_exit = function()
          vim.schedule(function()
            notify.stop_spinner(spin)
            if not attached then notify.warn("func host exited before becoming ready") end
          end)
        end,
      })
    end)
  end,
})
