local cmd    = require("dotnet.commands.init")
local runner = require("dotnet.core.runner")
local picker = require("dotnet.ui.picker")

-- Walk up from dir until host.json is found (Azure Functions project root)
local function find_func_root(dir)
  local d = vim.fn.fnamemodify(dir, ":p"):gsub("/$", "")
  while d ~= "" do
    if vim.fn.filereadable(d .. "/host.json") == 1 then return d end
    local parent = vim.fn.fnamemodify(d, ":h")
    if parent == d then break end
    d = parent
  end
  return dir  -- fallback to original dir
end

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
      local func_root = find_func_root(vim.fn.fnamemodify(proj, ":h"))
      runner.term({ "func", "start" }, {
        cwd   = func_root,
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
      local func_root = find_func_root(vim.fn.fnamemodify(proj, ":h"))
      local name      = vim.fn.fnamemodify(proj, ":t:r")
      local notify   = require("dotnet.notify")
      local ok, dap  = pcall(require, "dap")
      if not ok then notify.warn("nvim-dap not available"); return end

      -- Start func in a visible terminal so the user can see output
      runner.term({ "func", "start" }, {
        cwd   = func_root,
        label = "func start — " .. name,
      })

      notify.info("func host starting — will auto-attach when ready…")

      -- Poll for the dotnet worker process spawned by func (up to 40s)
      local attempts   = 0
      local max        = 40
      local attached   = false
      local func_pid   = nil

      -- Try to find the func process pid by name + cwd match
      local function find_dotnet_pid()
        local lines = {}
        vim.fn.jobwait({ vim.fn.jobstart(
          { "sh", "-c", "ps -eo pid,ppid,cmd | grep -v grep | grep dotnet" },
          { stdout_buffered = true,
            on_stdout = function(_, data)
              for _, l in ipairs(data) do if l ~= "" then table.insert(lines, l) end end
            end }
        ) }, 2000)
        for _, l in ipairs(lines) do
          -- look for dotnet process running something from proj_dir
          if l:find(func_root:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1"), 1, true) or
             l:find("func", 1, true) then
            local pid = l:match("^%s*(%d+)")
            if pid then return tonumber(pid) end
          end
        end
        -- fallback: any dotnet host process
        for _, l in ipairs(lines) do
          local pid = l:match("^%s*(%d+)")
          if pid then return tonumber(pid) end
        end
      end

      local function try_attach()
        if attached then return end
        attempts = attempts + 1
        if attempts > max then
          notify.warn("func host did not start in time — use Debug › Attach manually")
          return
        end

        local pid = find_dotnet_pid()
        if not pid then
          vim.defer_fn(try_attach, 1000)
          return
        end

        attached = true
        notify.info("func host ready (pid " .. pid .. ") — attaching debugger")
        dap.run({
          type      = "coreclr",
          name      = "Debug Azure Function: " .. name,
          request   = "attach",
          processId = pid,
        })
      end

      -- Give func a couple seconds to start spawning dotnet before first poll
      vim.defer_fn(try_attach, 3000)
    end)
  end,
})
