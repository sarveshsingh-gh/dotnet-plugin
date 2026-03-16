-- DAP + DAP-UI setup for .NET / netcoredbg.
local M = {}

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
          chosen = require("dotnet.ui.picker").pick_sync(runnable,
            function(p) return vim.fn.fnamemodify(p, ":t:r") end,
            "Debug project:")
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

  -- ── DAP-UI ──────────────────────────────────────────────────────────────────
  local ok_ui, dapui = pcall(require, "dapui")
  if ok_ui then
    dapui.setup({
      icons = { expanded = "▾", collapsed = "▸", current_frame = "▸" },
      layouts = {
        {
          elements = {
            { id = "scopes",      size = 0.40 },
            { id = "breakpoints", size = 0.20 },
            { id = "stacks",      size = 0.25 },
            { id = "watches",     size = 0.15 },
          },
          size     = 40,
          position = "left",
        },
        {
          elements = { { id = "repl", size = 0.6 }, { id = "console", size = 0.4 } },
          size     = 12,
          position = "bottom",
        },
      },
    })

    dap.listeners.after.event_initialized["dotnet_dapui"] = function()
      dapui.open({ layout = 1 })
    end
    dap.listeners.before.event_terminated["dotnet_dapui"] = function() dapui.close() end
    dap.listeners.before.event_exited["dotnet_dapui"]     = function() dapui.close() end
  end

  -- ── Register debug commands in palette ──────────────────────────────────────
  local cmd = require("dotnet.commands.init")
  cmd.register("debug.continue",    { category="debug", icon=" ",  desc="Continue / Start",      run = function() dap.continue() end })
  cmd.register("debug.stop",        { category="debug", icon="󰓛 ", desc="Stop",                   run = function() dap.terminate() end })
  cmd.register("debug.step_over",   { category="debug", icon="󰆷 ", desc="Step Over",              run = function() dap.step_over() end })
  cmd.register("debug.step_into",   { category="debug", icon="󰆹 ", desc="Step Into",              run = function() dap.step_into() end })
  cmd.register("debug.step_out",    { category="debug", icon="󰆸 ", desc="Step Out",               run = function() dap.step_out() end })
  cmd.register("debug.breakpoint",  { category="debug", icon="● ", desc="Toggle Breakpoint",      run = function() dap.toggle_breakpoint() end })
  cmd.register("debug.bp_cond",     { category="debug", icon="◆ ", desc="Conditional Breakpoint", run = function()
    dap.set_breakpoint(vim.fn.input("Condition: "))
  end })
  cmd.register("debug.clear_bps",  { category="debug", icon="󰅙 ", desc="Clear All Breakpoints",  run = function() dap.clear_breakpoints() end })
  if ok_ui then
    cmd.register("debug.ui_toggle", { category="debug", icon="󰙀 ", desc="Toggle Debug UI",        run = function() dapui.toggle() end })
    cmd.register("debug.eval",      { category="debug", icon=" ", desc="Evaluate Expression",    run = function() dapui.eval() end })
  end
end

return M
