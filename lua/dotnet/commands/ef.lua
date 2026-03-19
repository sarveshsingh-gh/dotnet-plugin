local cmd    = require("dotnet.commands.init")
local runner = require("dotnet.core.runner")
local picker = require("dotnet.ui.picker")

local function reg(id, def) cmd.register(id, vim.tbl_extend("force", { category = "ef" }, def)) end

local function pick_proj_then(prompt, fn)
  picker.project({ prompt = prompt }, function(proj)
    if proj then fn(proj) end
  end)
end

local function ef(proj, args, label, startup_proj)
  local proj_dir = vim.fn.fnamemodify(proj, ":h")
  local cmd_args = vim.list_extend({ "dotnet", "ef" }, args)
  vim.list_extend(cmd_args, { "--project", proj })
  if startup_proj then
    vim.list_extend(cmd_args, { "--startup-project", startup_proj })
  end
  runner.bg(cmd_args, { cwd = proj_dir, label = label })
end

-- Find the runnable startup project in the solution (for --startup-project).
-- If there's only one runnable project, returns it. Otherwise returns nil.
local function find_startup_proj()
  local sln = require("dotnet").sln()
  if not sln then return nil end
  local projs   = require("dotnet.core.solution").projects(sln)
  local proj_m  = require("dotnet.core.project")
  local runnable = vim.tbl_filter(proj_m.runnable, projs)
  return #runnable == 1 and runnable[1] or nil
end

-- Two-step picker: select the migrations project then the startup project.
local function pick_infra_proj_then(prompt, fn)
  picker.project({ prompt = prompt }, function(proj)
    if not proj then return end
    picker.project({ prompt = "Startup project:" }, function(startup)
      if not startup then return end
      fn(proj, startup ~= proj and startup or nil)
    end)
  end)
end

-- ── Migrations ───────────────────────────────────────────────────────────────

reg("ef.migration.add", {
  icon = "󰆒 ",
  desc = "EF: Add migration",
  run  = function()
    pick_infra_proj_then("Add migration to project:", function(proj, startup)
      vim.ui.input({ prompt = "Migration name: " }, function(name)
        if name and name ~= "" then
          ef(proj, { "migrations", "add", name }, "EF add migration: " .. name, startup)
        end
      end)
    end)
  end,
})

reg("ef.migration.remove", {
  icon = "󰆓 ",
  desc = "EF: Remove last migration",
  run  = function()
    pick_infra_proj_then("Remove last migration from:", function(proj, startup)
      ef(proj, { "migrations", "remove" }, "EF remove migration", startup)
    end)
  end,
})

reg("ef.migration.list", {
  icon = "󰋙 ",
  desc = "EF: List migrations",
  run  = function()
    pick_infra_proj_then("List migrations for:", function(proj, startup)
      local proj_dir = vim.fn.fnamemodify(proj, ":h")
      local args = { "dotnet", "ef", "migrations", "list", "--project", proj }
      if startup then vim.list_extend(args, { "--startup-project", startup }) end
      local lines = {}
      vim.fn.jobwait({ vim.fn.jobstart(args, {
        cwd = proj_dir,
        stdout_buffered = true,
        stderr_buffered = true,
        on_stdout = function(_, data) vim.list_extend(lines, data) end,
        on_stderr = function(_, data) vim.list_extend(lines, data) end,
        on_exit = function(_, code)
          vim.schedule(function()
            -- strip empty trailing lines
            while #lines > 0 and lines[#lines] == "" do table.remove(lines) end
            if #lines == 0 then lines = { "(no migrations found)" } end
            -- show in a floating window
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
            vim.bo[buf].filetype = "dotnet_migrations"
            local width  = math.max(50, math.min(80, vim.o.columns - 10))
            local height = math.min(#lines + 2, 20)
            vim.api.nvim_open_win(buf, true, {
              relative = "editor",
              width    = width,
              height   = height,
              row      = math.floor((vim.o.lines - height) / 2),
              col      = math.floor((vim.o.columns - width) / 2),
              style    = "minimal",
              border   = "rounded",
              title    = " EF Migrations ",
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

reg("ef.migration.script", {
  icon = "󰦽 ",
  desc = "EF: Generate SQL script",
  run  = function()
    pick_proj_then("Generate SQL script for:", function(proj)
      local proj_dir  = vim.fn.fnamemodify(proj, ":h")
      local out       = proj_dir .. "/migration_script.sql"
      local cmd_args  = { "dotnet", "ef", "migrations", "script",
                          "--output", out, "--project", proj }
      runner.bg(cmd_args, {
        cwd   = proj_dir,
        label = "EF generate SQL script",
        on_exit = function(code)
          if code == 0 then
            vim.schedule(function()
              vim.cmd("edit " .. vim.fn.fnameescape(out))
            end)
          end
        end,
      })
    end)
  end,
})

-- ── Database ──────────────────────────────────────────────────────────────────

reg("ef.db.update", {
  icon = "󰆑 ",
  desc = "EF: Update database",
  run  = function()
    pick_infra_proj_then("Update database for:", function(proj, startup)
      ef(proj, { "database", "update" }, "EF database update", startup)
    end)
  end,
})

reg("ef.db.update_to", {
  icon = "󰆑 ",
  desc = "EF: Update database to migration",
  run  = function()
    pick_infra_proj_then("Update database to migration:", function(proj, startup)
      vim.ui.input({ prompt = "Target migration (or '0' to revert all): " }, function(target)
        if target and target ~= "" then
          ef(proj, { "database", "update", target }, "EF database update → " .. target, startup)
        end
      end)
    end)
  end,
})

reg("ef.db.drop", {
  icon = "󰆑 ",
  desc = "EF: Drop database",
  run  = function()
    pick_infra_proj_then("Drop database for:", function(proj, startup)
      vim.ui.select({ "Yes, drop it", "Cancel" }, { prompt = "Drop database? This is irreversible!" }, function(choice)
        if choice and choice:match("^Yes") then
          ef(proj, { "database", "drop", "--force" }, "EF database drop", startup)
        end
      end)
    end)
  end,
})

-- ── Scaffold ──────────────────────────────────────────────────────────────────

reg("ef.scaffold", {
  icon = "󰐅 ",
  desc = "EF: Scaffold DbContext from database",
  run  = function()
    pick_proj_then("Scaffold DbContext in:", function(proj)
      vim.ui.input({ prompt = "Connection string: " }, function(conn)
        if not conn or conn == "" then return end
        vim.ui.input({ prompt = "Provider (e.g. Microsoft.EntityFrameworkCore.SqlServer): ",
                       default = "Microsoft.EntityFrameworkCore.SqlServer" }, function(provider)
          if not provider or provider == "" then return end
          vim.ui.input({ prompt = "Output folder (default: Models): ", default = "Models" }, function(out)
            out = (out and out ~= "") and out or "Models"
            local proj_dir = vim.fn.fnamemodify(proj, ":h")
            local cmd_args = { "dotnet", "ef", "dbcontext", "scaffold",
                               conn, provider,
                               "--output-dir", out,
                               "--force",
                               "--project", proj }
            runner.bg(cmd_args, { cwd = proj_dir, label = "EF scaffold DbContext" })
          end)
        end)
      end)
    end)
  end,
})
