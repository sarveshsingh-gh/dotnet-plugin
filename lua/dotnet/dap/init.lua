-- DAP + DAP-UI setup for .NET / netcoredbg.
local M = {}

--- Get the test method name at the current cursor position (treesitter or regex).
function M.test_method_at_cursor()
  -- Treesitter approach
  local ok, parser = pcall(vim.treesitter.get_parser, 0, "c_sharp")
  if ok and parser then
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local tree = parser:parse()[1]
    local node = tree:root():descendant_for_range(row, 0, row, 999)
    while node do
      if node:type() == "method_declaration" then
        for child in node:iter_children() do
          if child:type() == "identifier" then
            return vim.treesitter.get_node_text(child, 0)
          end
        end
      end
      node = node:parent()
    end
  end
  -- Regex fallback: search upward for method signature
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, row, false)
  for i = #lines, 1, -1 do
    local m = lines[i]:match("public%s+.-%s+(%w+)%s*%(")
    if m and m ~= "class" then return m end
  end
  return nil
end

--- Debug a test project using VSTEST_HOST_DEBUG=1 attach approach.
--- filter: optional dotnet test --filter value (e.g. "FullyQualifiedName~MethodName")
function M.debug_test_project(proj_path, filter)
  local ok, dap = pcall(require, "dap")
  if not ok then require("dotnet.notify").warn("nvim-dap not available"); return end
  local notify  = require("dotnet.notify")
  local proj_dir = vim.fn.fnamemodify(proj_path, ":h")
  local name     = vim.fn.fnamemodify(proj_path, ":t:r")
  local label    = filter and (name .. " [" .. filter .. "]") or name
  local spin     = notify.start_spinner("Waiting for test host… " .. label)
  local attached = false
  local cmd = { "dotnet", "test", proj_path, "--no-build" }
  if filter then vim.list_extend(cmd, { "--filter", filter }) end
  vim.fn.jobstart(cmd, {
    cwd = proj_dir,
    env = vim.tbl_extend("force", vim.fn.environ(), { VSTEST_HOST_DEBUG = "1" }),
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      for _, line in ipairs(data or {}) do
        local pid = line:match("[Pp]rocess[Ii][Dd]%s*:%s*(%d+)")
                 or line:match("[Pp]rocess[%s_][Ii][Dd][%s:=]+(%d+)")
                 or line:match("PID[%s:=]+(%d+)")
        if pid and not attached then
          attached = true
          vim.schedule(function()
            notify.stop_spinner(spin)
            local trx_key = "dt_trx_" .. proj_path
            dap.listeners.before["event_terminated"][trx_key] = function()
              dap.listeners.before["event_terminated"][trx_key] = nil
              vim.schedule(function()
                local results_dir = vim.fn.tempname()
                vim.fn.mkdir(results_dir, "p")
                local signs = require("dotnet.ui.test_signs")
                signs.mark_running(proj_path)
                vim.fn.jobstart({ "dotnet", "test", "--nologo", "--no-build",
                                  "--logger", "trx", "--results-directory", results_dir, proj_path }, {
                  cwd = proj_dir,
                  on_exit = function(_, _code)
                    vim.schedule(function()
                      local trx = vim.fn.glob(results_dir .. "/*.trx", false, true)
                      local results = {}
                      if trx and #trx > 0 then
                        local ok3, lines = pcall(vim.fn.readfile, trx[1])
                        vim.fn.delete(results_dir, "rf")
                        if ok3 then
                          local id_to_fqn, cur_id = {}, nil
                          for _, l in ipairs(lines) do
                            local id = l:match('<UnitTest[^>]+%sid="([^"]+)"')
                            if id then cur_id = id end
                            if cur_id then
                              local cls  = l:match('className="([^"]+)"')
                              local meth = l:match('<TestMethod[^>]+%sname="([^"]+)"')
                              if cls and meth then id_to_fqn[cur_id] = cls .. "." .. meth; cur_id = nil end
                            end
                          end
                          for _, l in ipairs(lines) do
                            if l:find("UnitTestResult") and l:find('testId=') and l:find('outcome=') then
                              local tid = l:match('testId="([^"]+)"')
                              local out = l:match('outcome="([^"]+)"')
                              if tid and out and id_to_fqn[tid] then
                                local st = out:lower()
                                results[id_to_fqn[tid]] = st == "notexecuted" and "skipped" or st
                              end
                            end
                          end
                        end
                      else
                        vim.fn.delete(results_dir, "rf")
                      end
                      signs.annotate(results)
                    end)
                  end,
                })
              end)
            end
            dap.run({ type = "coreclr", name = "Debug Tests: " .. name, request = "attach", processId = tonumber(pid) })
          end)
        end
      end
    end,
    on_exit = function(_, _code)
      vim.schedule(function()
        notify.stop_spinner(spin)
        if not attached then notify.warn("Test host did not print a PID — try building first") end
      end)
    end,
  })
end

function M.setup(cfg)
  cfg = cfg or {}

  -- Signs first (no dap dependency)
  require("dotnet.dap.signs").setup(cfg)

  if not cfg.enabled then return end

  local ok_dap, dap = pcall(require, "dap")
  if not ok_dap then return end

  -- ── Find netcoredbg ─────────────────────────────────────────────────────────
  local dbg_path
  for _, p in ipairs(cfg.netcoredbg_paths or {}) do
    if p and p ~= "" and vim.fn.executable(p) == 1 then
      dbg_path = p
      break
    end
  end
  if not dbg_path then
    require("dotnet.notify").warn("netcoredbg not found — debugging disabled")
    return
  end

  local adapter = cfg.adapter_name or "coreclr"

  -- ── Register adapter ────────────────────────────────────────────────────────
  dap.adapters[adapter] = {
    type    = "executable",
    command = dbg_path,
    args    = { "--interpreter=vscode" },
  }

  -- ── Configurations ──────────────────────────────────────────────────────────
  dap.configurations.cs = dap.configurations.cs or {}

  -- Only add our configs if not already present
  local has_launch = false
  local has_attach = false
  for _, c in ipairs(dap.configurations.cs) do
    if c.request == "launch" then has_launch = true end
    if c.request == "attach" then has_attach = true end
  end

  if not has_launch then
    table.insert(dap.configurations.cs, {
      type    = adapter,
      name    = ".NET Launch (dotnet.nvim)",
      request = "launch",
      program = function()
        -- Pick the DLL to launch
        local sln = require("dotnet.core.solution").find()
        if not sln then
          return vim.fn.input("Path to DLL: ", vim.fn.getcwd() .. "/", "file")
        end
        local projs  = require("dotnet.core.solution").projects(sln)
        local proj_m = require("dotnet.core.project")
        local runnable = vim.tbl_filter(proj_m.runnable, projs)
        if #runnable == 0 then
          return vim.fn.input("Path to DLL: ", vim.fn.getcwd() .. "/", "file")
        end
        local chosen
        if #runnable == 1 then
          chosen = runnable[1]
        else
          vim.ui.select(runnable, {
            prompt = "Debug project:",
            format_item = function(p) return vim.fn.fnamemodify(p, ":t:r") end,
          }, function(sel) chosen = sel end)
        end
        if not chosen then return dap.ABORT end
        -- Build and find the DLL
        local proj_dir = vim.fn.fnamemodify(chosen, ":h")
        local name     = vim.fn.fnamemodify(chosen, ":t:r")
        -- look for the dll under bin/Debug or bin/Release
        local dlls = vim.fn.glob(proj_dir .. "/bin/**/" .. name .. ".dll", false, true)
        if #dlls > 0 then
          -- pick most recently modified
          table.sort(dlls, function(a, b)
            return vim.fn.getftime(a) > vim.fn.getftime(b)
          end)
          return dlls[1]
        end
        return vim.fn.input("Path to DLL: ", proj_dir .. "/bin/", "file")
      end,
      cwd              = "${workspaceFolder}",
      stopAtEntry      = false,
      console          = cfg.console or "integratedTerminal",
    })
  end

  if not has_attach then
    table.insert(dap.configurations.cs, {
      type      = adapter,
      name      = ".NET Attach to process",
      request   = "attach",
      processId = require("dap.utils").pick_process,
    })
  end

  -- NOTE: dapui setup, layouts, and open/close listeners are intentionally NOT
  -- done here — the host config (nvim-config) owns dapui setup to avoid conflicts.

  -- ── Register debug commands in palette ──────────────────────────────────────
  local cmd = require("dotnet.commands.init")
  cmd.register("debug.launch",      { category="debug", icon="󰃤 ", desc="Debug", run = function()
    local sln    = require("dotnet").sln()
    local proj_m = require("dotnet.core.project")
    local notify = require("dotnet.notify")
    local projs  = sln and require("dotnet.core.solution").projects(sln) or {}
    local runnable = vim.tbl_filter(proj_m.runnable, projs)

    local function do_launch(proj_path, profile_name, env_vars, app_url)
      local proj_dir = vim.fn.fnamemodify(proj_path, ":h")
      local name     = vim.fn.fnamemodify(proj_path, ":t:r")
      local spin = notify.start_spinner("Building " .. name .. "…")
      local build_err = {}
      vim.fn.jobstart({ "dotnet", "build", proj_path, "--nologo" }, {
        cwd = proj_dir,
        stdout_buffered = true,
        stderr_buffered = true,
        on_stderr = function(_, data) for _, l in ipairs(data or {}) do if l ~= "" then build_err[#build_err+1] = l end end end,
        on_exit = function(_, code)
          vim.schedule(function()
            local ok3, err3 = pcall(function()
              notify.stop_spinner(spin)
              if code ~= 0 then
                notify.fail("Build failed: " .. (build_err[1] or "unknown error"))
                return
              end
              local dlls = vim.fn.glob(proj_dir .. "/bin/**/" .. name .. ".dll", false, true)
              if #dlls == 0 then notify.warn("DLL not found after build"); return end
              table.sort(dlls, function(a, b) return vim.fn.getftime(a) > vim.fn.getftime(b) end)
              local dll = dlls[1]
              local url_env = app_url and { ASPNETCORE_URLS = app_url } or {}
              local env = vim.tbl_extend("force", vim.fn.environ(), {
                ASPNETCORE_ENVIRONMENT = "Development",
                DOTNET_ENVIRONMENT     = "Development",
              }, url_env, env_vars or {})
              if app_url then notify.info("API → " .. app_url) end
              local adapter = cfg.adapter_name or "coreclr"
              dap.run({
                type        = adapter,
                name        = "Debug: " .. name .. (profile_name and (" [" .. profile_name .. "]") or ""),
                request     = "launch",
                program     = dll,
                args        = {},
                cwd         = proj_dir,
                stopAtEntry = false,
                console     = "integratedTerminal",
                env         = env,
              })
            end)
            if not ok3 then notify.error("Launch: " .. tostring(err3)) end
          end)
        end,
      })
    end

    local function pick_profile_then_launch(proj_path)
      local proj_dir     = vim.fn.fnamemodify(proj_path, ":h")
      local settings_path = proj_dir .. "/Properties/launchSettings.json"
      local profiles = {}
      if vim.fn.filereadable(settings_path) == 1 then
        local ok, raw = pcall(vim.fn.readfile, settings_path)
        if ok then
          local ok2, data = pcall(vim.json.decode, table.concat(raw, "\n"))
          if ok2 and data and data.profiles then
            for pname, pdata in pairs(data.profiles) do
              if pdata.commandName == "Project" then
                local env_vars = pdata.environmentVariables or {}
                table.insert(profiles, { name = pname, url = pdata.applicationUrl, env = env_vars })
              end
            end
          end
        end
      end
      if #profiles == 0 then
        do_launch(proj_path, nil, {}, nil)
      elseif #profiles == 1 then
        local p = profiles[1]
        local url = p.url and p.url:match("(https?://[^;]+)") or nil
        do_launch(proj_path, p.name, p.env, url)
      else
        vim.ui.select(profiles, {
          prompt = "Launch profile:",
          format_item = function(p) return p.name .. (p.url and ("  " .. p.url) or "") end,
        }, function(sel)
          if not sel then return end
          local url = sel.url and sel.url:match("(https?://[^;]+)") or nil
          do_launch(proj_path, sel.name, sel.env, url)
        end)
      end
    end

    if #runnable == 0 then
      notify.warn("No runnable projects found in solution")
    elseif #runnable == 1 then
      pick_profile_then_launch(runnable[1])
    else
      vim.ui.select(runnable, {
        prompt = "Debug project:",
        format_item = function(p) return vim.fn.fnamemodify(p, ":t:r") end,
      }, function(chosen) if chosen then pick_profile_then_launch(chosen) end end)
    end
  end })
  cmd.register("debug.continue",    { category="debug", icon="󰐊 ", desc="Continue / Start",      run = function() dap.continue() end })
  cmd.register("debug.stop",        { category="debug", icon="󰓛 ", desc="Stop",                   run = function() dap.terminate() end })
  cmd.register("debug.step_over",   { category="debug", icon="󰆷 ", desc="Step Over",              run = function() dap.step_over() end })
  cmd.register("debug.step_into",   { category="debug", icon="󰆹 ", desc="Step Into",              run = function() dap.step_into() end })
  cmd.register("debug.step_out",    { category="debug", icon="󰆸 ", desc="Step Out",               run = function() dap.step_out() end })
  cmd.register("debug.breakpoint",  { category="debug", icon="󰝤 ", desc="Toggle Breakpoint",      run = function() dap.toggle_breakpoint() end })
  cmd.register("debug.bp_cond",     { category="debug", icon="󰟃 ", desc="Conditional Breakpoint", run = function()
    dap.set_breakpoint(vim.fn.input("Condition: "))
  end })
  cmd.register("debug.clear_bps",  { category="debug", icon="󰅙 ", desc="Clear All Breakpoints",  run = function() dap.clear_breakpoints() end })
  cmd.register("debug.ui_toggle",   { category="debug", icon="󰙀 ", desc="Toggle Debug UI",        run = function() pcall(function() require("dapui").toggle() end) end })
  cmd.register("debug.eval",        { category="debug", icon="󰃧 ", desc="Evaluate Expression",    run = function() pcall(function() require("dapui").eval() end) end })
end

return M
