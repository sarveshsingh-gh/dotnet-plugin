local cmd    = require("dotnet.commands.init")
local runner = require("dotnet.core.runner")
local picker = require("dotnet.ui.picker")

-- Start azurite if not already running, then call cb() after a brief delay.
-- Cross-platform: works on Linux, macOS, and Windows.
local function ensure_azurite(cb)
  local notify = require("dotnet.notify")
  if vim.fn.executable("azurite") == 0 then
    notify.warn("azurite not found — install with: npm install -g azurite")
    cb(); return
  end

  local is_win = vim.fn.has("win32") == 1
  local check  = is_win
    and { "powershell", "-Command", "Get-Process azurite -ErrorAction SilentlyIgnore" }
    or  { "pgrep", "-x", "azurite" }

  local running = false
  vim.fn.jobwait({ vim.fn.jobstart(check, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      for _, l in ipairs(data) do if l ~= "" then running = true end end
    end,
  }) }, 2000)

  if running then cb(); return end

  local dir = vim.fn.expand("~/.azurite")
  vim.fn.mkdir(dir, "p")
  vim.fn.jobstart({ "azurite", "--location", dir, "--silent" }, { detach = true })
  notify.info("Azurite started")
  -- Give azurite ~1s to bind its ports before func connects
  vim.defer_fn(cb, 1000)
end

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
    local function is_func(p)
      local dir = vim.fn.fnamemodify(p, ":h")
      return vim.fn.filereadable(dir .. "/host.json") == 1
    end
    picker.project({ prompt = "Start Azure Function:", filter = is_func }, function(proj)
      local func_root = find_func_root(vim.fn.fnamemodify(proj, ":h"))
      ensure_azurite(function()
        runner.term({ "func", "start" }, {
          cwd   = func_root,
          label = "func start — " .. vim.fn.fnamemodify(proj, ":t:r"),
        })
      end)
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
    local function is_func(p)
      return vim.fn.filereadable(vim.fn.fnamemodify(p, ":h") .. "/host.json") == 1
    end
    picker.project({ prompt = "Debug Azure Function:", filter = is_func }, function(proj)
      local func_root = find_func_root(vim.fn.fnamemodify(proj, ":h"))
      local name      = vim.fn.fnamemodify(proj, ":t:r")
      local notify   = require("dotnet.notify")
      local ok, dap  = pcall(require, "dap")
      if not ok then notify.warn("nvim-dap not available"); return end

      ensure_azurite(function()
        -- Start func in a visible terminal so the user can see output
        runner.term({ "func", "start" }, {
          cwd   = func_root,
          label = "func start — " .. name,
        })

        notify.info("func host starting — auto-attach will begin in 5s…")

        -- Retry-based worker process detection.
        -- dotnet-isolated worker cmd contains both the DLL name and "--host LocalFunctionsHost".
        -- We retry every 2s for up to ~21s to handle slow startup.
        local dll         = name .. ".dll"
        local max_attempts = 8
        local attached    = false

        local function try_attach(attempt)
          if attached then return end
          if attempt > max_attempts then
            notify.warn("Worker process not found — is func running? Use M-p → Debug attach to attach manually.")
            return
          end

          local procs = {}
          local grep  = "ps -eo pid,cmd | grep -v grep | grep -E 'LocalFunctionsHost|" .. dll .. "'"
          vim.fn.jobwait({ vim.fn.jobstart({ "sh", "-c", grep }, {
            stdout_buffered = true,
            on_stdout = function(_, data)
              for _, l in ipairs(data) do
                local pid, pcmd = l:match("^%s*(%d+)%s+(.+)$")
                if pid then table.insert(procs, { pid = tonumber(pid), cmd = vim.trim(pcmd) }) end
              end
            end,
          }) }, 2000)

          if #procs == 0 then
            if attempt < max_attempts then
              notify.info(string.format("Waiting for worker… (%d/%d)", attempt, max_attempts))
              vim.defer_fn(function() try_attach(attempt + 1) end, 2000)
            else
              notify.warn("Worker process not found — use M-p → Debug attach to attach manually.")
            end
            return
          end

          -- Prefer the process whose cmd contains the DLL (the actual user code process)
          local target = nil
          for _, p in ipairs(procs) do
            if p.cmd:find(dll, 1, true) then target = p; break end
          end
          target = target or procs[1]

          attached = true
          notify.info("Attaching debugger to " .. name .. " (pid " .. target.pid .. ")…")
          dap.run({
            type      = "coreclr",
            name      = "Debug Azure Function: " .. name,
            request   = "attach",
            processId = target.pid,
            justMyCode = false,
          })
        end

        vim.defer_fn(function() try_attach(1) end, 5000)
      end) -- ensure_azurite
    end)
  end,
})

local FUNC_TEMPLATES = {
  { label = "HTTP trigger",              template = "HTTP trigger" },
  { label = "Timer trigger",             template = "Timer trigger" },
  { label = "Queue trigger",             template = "Queue trigger" },
  { label = "Blob trigger",              template = "Blob trigger" },
  { label = "Service Bus Queue trigger", template = "Service Bus Queue trigger" },
  { label = "Service Bus Topic trigger", template = "Service Bus Topic trigger" },
  { label = "Event Hub trigger",         template = "Event Hub trigger" },
  { label = "Event Grid trigger",        template = "Event Grid trigger" },
  { label = "Cosmos DB trigger",         template = "Cosmos DB trigger" },
  { label = "Durable — Orchestrator",    template = "Durable Functions Orchestrator" },
  { label = "Durable — Activity",        template = "Durable Functions Activity" },
  { label = "Durable — HTTP start",      template = "Durable Functions HttpStart" },
}

reg("run.func_new", {
  icon = "󰡱 ",
  desc = "New Azure Function (func new)",
  run  = function()
    if vim.fn.executable("func") == 0 then
      require("dotnet.notify").warn("Azure Functions Core Tools ('func') not found in PATH")
      return
    end

    local function is_func(p)
      return vim.fn.filereadable(vim.fn.fnamemodify(p, ":h") .. "/host.json") == 1
    end

    picker.project({ prompt = "New function in project:", filter = is_func }, function(proj)
      local func_root = find_func_root(vim.fn.fnamemodify(proj, ":h"))

      vim.ui.select(FUNC_TEMPLATES, {
        prompt      = "Trigger type:",
        format_item = function(t) return t.label end,
      }, function(tpl)
        if not tpl then return end

        vim.ui.input({ prompt = "Function name: " }, function(name)
          if not name or name == "" then return end

          runner.bg(
            { "func", "new", "--template", tpl.template, "--name", name },
            {
              cwd            = func_root,
              label          = "func new " .. name,
              notify_success = true,
              on_exit        = function(code)
                if code == 0 then
                  local file = func_root .. "/" .. name .. ".cs"
                  if vim.fn.filereadable(file) == 1 then
                    vim.schedule(function() vim.cmd("edit " .. vim.fn.fnameescape(file)) end)
                  end
                end
              end,
            }
          )
        end)
      end)
    end)
  end,
})
