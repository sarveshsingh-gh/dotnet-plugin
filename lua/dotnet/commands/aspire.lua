-- dotnet.nvim — .NET Aspire CLI commands
-- Requires the `aspire` CLI (https://aspire.dev/get-started/install-cli)
local cmd    = require("dotnet.commands.init")
local runner = require("dotnet.core.runner")
local picker = require("dotnet.ui.picker")
local notify = require("dotnet.notify")

local function reg(id, def) cmd.register(id, vim.tbl_extend("force", { category = "aspire" }, def)) end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function aspire_installed()
  local handle = io.popen("aspire --version 2>/dev/null")
  if not handle then return false end
  local out = handle:read("*a"); handle:close()
  return out ~= nil and out ~= ""
end

local function check_installed()
  if not aspire_installed() then
    notify.warn("Aspire CLI not found — install from https://aspire.dev/get-started/install-cli")
    return false
  end
  return true
end

local function sln_dir()
  local sln = require("dotnet").sln()
  if not sln then return vim.fn.getcwd() end
  return vim.fn.fnamemodify(sln, ":h")
end

-- ── New / Init ────────────────────────────────────────────────────────────────

local ASPIRE_TEMPLATES = {
  "aspire-starter",
  "aspire",
  "aspire-apphost",
  "aspire-servicedefaults",
  "aspire-mstest",
  "aspire-nunit",
  "aspire-xunit",
}

reg("aspire.new", {
  icon = "󰐅 ",
  desc = "Aspire: New project from template",
  run  = function()
    if not check_installed() then return end
    vim.ui.select(ASPIRE_TEMPLATES, { prompt = "Aspire template:" }, function(template)
      if not template then return end
      vim.ui.input({ prompt = "Project name: " }, function(name)
        if not name or name == "" then return end
        local cwd = vim.fn.getcwd()
        vim.ui.input({ prompt = "Output directory (default: " .. name .. "): ", default = name }, function(out)
          out = (out and out ~= "") and out or name
          runner.term(
            { "aspire", "new", template, "--name", name, "--output", out },
            { cwd = cwd, label = "Aspire new: " .. template .. " → " .. name }
          )
        end)
      end)
    end)
  end,
})

reg("aspire.init", {
  icon = "󰐅 ",
  desc = "Aspire: Init in existing solution",
  run  = function()
    if not check_installed() then return end
    picker.solution(function(sln)
      local dir = vim.fn.fnamemodify(sln, ":h")
      runner.bg(
        { "aspire", "init" },
        {
          cwd   = dir,
          label = "Aspire init: " .. vim.fn.fnamemodify(sln, ":t"),
          notify_success = true,
          on_exit = function(code)
            if code == 0 then
              pcall(function() require("dotnet.ui.explorer").refresh_if_open() end)
            end
          end,
        }
      )
    end)
  end,
})

-- ── Run ───────────────────────────────────────────────────────────────────────

reg("aspire.run", {
  icon = "󰐊 ",
  desc = "Aspire: Run AppHost (local dev)",
  run  = function()
    if not check_installed() then return end
    picker.project({ prompt = "AppHost project:" }, function(proj)
      if not proj then return end
      local proj_dir = vim.fn.fnamemodify(proj, ":h")
      runner.term(
        { "aspire", "run", "--project", proj },
        { cwd = proj_dir, label = "Aspire run: " .. vim.fn.fnamemodify(proj, ":t:r") }
      )
    end)
  end,
})

-- ── Add integration ───────────────────────────────────────────────────────────

reg("aspire.add", {
  icon = "󰐒 ",
  desc = "Aspire: Add integration to AppHost",
  run  = function()
    if not check_installed() then return end
    picker.project({ prompt = "AppHost project:" }, function(proj)
      if not proj then return end
      vim.ui.input({ prompt = "Integration name (e.g. redis, postgres, rabbitmq): " }, function(integration)
        if not integration or integration == "" then return end
        local proj_dir = vim.fn.fnamemodify(proj, ":h")
        runner.bg(
          { "aspire", "add", integration, "--project", proj },
          {
            cwd   = proj_dir,
            label = "Aspire add: " .. integration,
            notify_success = true,
          }
        )
      end)
    end)
  end,
})

-- ── Publish ───────────────────────────────────────────────────────────────────

reg("aspire.publish", {
  icon = "󰕒 ",
  desc = "Aspire: Publish (generate deployment artifacts)",
  run  = function()
    if not check_installed() then return end
    picker.project({ prompt = "AppHost project:" }, function(proj)
      if not proj then return end
      local proj_dir  = vim.fn.fnamemodify(proj, ":h")
      local default_out = proj_dir .. "/publish"
      vim.ui.input({ prompt = "Output path: ", default = default_out }, function(out)
        out = (out and out ~= "") and out or default_out
        runner.bg(
          { "aspire", "publish", "--project", proj, "--output-path", out },
          {
            cwd   = proj_dir,
            label = "Aspire publish: " .. vim.fn.fnamemodify(proj, ":t:r"),
            notify_success = true,
            on_exit = function(code)
              if code == 0 then
                vim.schedule(function()
                  vim.cmd("edit " .. vim.fn.fnameescape(out))
                end)
              end
            end,
          }
        )
      end)
    end)
  end,
})

-- ── Deploy ────────────────────────────────────────────────────────────────────

reg("aspire.deploy", {
  icon = "󰅐 ",
  desc = "Aspire: Deploy to target",
  run  = function()
    if not check_installed() then return end
    picker.project({ prompt = "AppHost project:" }, function(proj)
      if not proj then return end
      local proj_dir = vim.fn.fnamemodify(proj, ":h")
      runner.term(
        { "aspire", "deploy", "--project", proj },
        { cwd = proj_dir, label = "Aspire deploy: " .. vim.fn.fnamemodify(proj, ":t:r") }
      )
    end)
  end,
})

-- ── Update ────────────────────────────────────────────────────────────────────

reg("aspire.update", {
  icon = "󰚰 ",
  desc = "Aspire: Update packages / CLI",
  run  = function()
    if not check_installed() then return end
    vim.ui.select(
      { "Update packages in solution", "Update Aspire CLI itself" },
      { prompt = "What to update:" },
      function(choice)
        if not choice then return end
        if choice:match("CLI") then
          runner.term({ "aspire", "update" }, { cwd = vim.fn.getcwd(), label = "Aspire CLI update" })
        else
          picker.solution(function(sln)
            local dir = vim.fn.fnamemodify(sln, ":h")
            runner.bg(
              { "aspire", "update", "--solution", sln },
              { cwd = dir, label = "Aspire update packages", notify_success = true }
            )
          end)
        end
      end
    )
  end,
})

-- ── Cache ─────────────────────────────────────────────────────────────────────

reg("aspire.cache.clear", {
  icon = "󰃢 ",
  desc = "Aspire: Clear CLI cache",
  run  = function()
    if not check_installed() then return end
    runner.bg(
      { "aspire", "cache", "clear" },
      { cwd = vim.fn.getcwd(), label = "Aspire cache clear", notify_success = true }
    )
  end,
})

-- ── Config ────────────────────────────────────────────────────────────────────

reg("aspire.config.get", {
  icon = "󰒓 ",
  desc = "Aspire: Get config value",
  run  = function()
    if not check_installed() then return end
    vim.ui.input({ prompt = "Config key: " }, function(key)
      if not key or key == "" then return end
      local lines = {}
      vim.fn.jobwait({ vim.fn.jobstart({ "aspire", "config", "get", key }, {
        cwd = sln_dir(),
        stdout_buffered = true,
        stderr_buffered = true,
        on_stdout = function(_, data) vim.list_extend(lines, data) end,
        on_stderr = function(_, data) vim.list_extend(lines, data) end,
        on_exit = function(_, code)
          vim.schedule(function()
            while #lines > 0 and lines[#lines] == "" do table.remove(lines) end
            if #lines == 0 then
              lines = code == 0 and { "(empty)" } or { "Key not found: " .. key }
            end
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
            local width  = math.max(40, math.min(80, vim.o.columns - 10))
            local height = math.min(#lines + 2, 15)
            vim.api.nvim_open_win(buf, true, {
              relative  = "editor",
              width     = width,
              height    = height,
              row       = math.floor((vim.o.lines - height) / 2),
              col       = math.floor((vim.o.columns - width) / 2),
              style     = "minimal",
              border    = "rounded",
              title     = " aspire config: " .. key .. " ",
              title_pos = "center",
            })
            vim.keymap.set("n", "q",     "<cmd>close<cr>", { buffer = buf, silent = true })
            vim.keymap.set("n", "<esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
          end)
        end,
      }) }, -1)
    end)
  end,
})

reg("aspire.config.set", {
  icon = "󰒓 ",
  desc = "Aspire: Set config value",
  run  = function()
    if not check_installed() then return end
    vim.ui.input({ prompt = "Config key: " }, function(key)
      if not key or key == "" then return end
      vim.ui.input({ prompt = "Value: " }, function(value)
        if value == nil then return end
        runner.bg(
          { "aspire", "config", "set", key, value },
          { cwd = sln_dir(), label = "Aspire config set " .. key, notify_success = true }
        )
      end)
    end)
  end,
})

-- ── MCP ───────────────────────────────────────────────────────────────────────

reg("aspire.mcp.init", {
  icon = "󰒉 ",
  desc = "Aspire: MCP server init",
  run  = function()
    if not check_installed() then return end
    runner.bg(
      { "aspire", "mcp", "init" },
      { cwd = sln_dir(), label = "Aspire MCP init", notify_success = true }
    )
  end,
})

reg("aspire.mcp.start", {
  icon = "󰒊 ",
  desc = "Aspire: MCP server start",
  run  = function()
    if not check_installed() then return end
    runner.term(
      { "aspire", "mcp", "start" },
      { cwd = sln_dir(), label = "Aspire MCP server" }
    )
  end,
})

-- ── Pipeline (aspire do) ──────────────────────────────────────────────────────

reg("aspire.do", {
  icon = "󰐊 ",
  desc = "Aspire: Execute pipeline step (aspire do)",
  run  = function()
    if not check_installed() then return end
    vim.ui.input({ prompt = "Pipeline step name: " }, function(step)
      if not step or step == "" then return end
      picker.solution(function(sln)
        local dir = vim.fn.fnamemodify(sln, ":h")
        runner.term(
          { "aspire", "do", step },
          { cwd = dir, label = "Aspire do: " .. step }
        )
      end)
    end)
  end,
})
