local cmd    = require("dotnet.commands.init")
local runner = require("dotnet.core.runner")
local picker = require("dotnet.ui.picker")

local function reg(id, def) cmd.register(id, vim.tbl_extend("force", { category = "ef" }, def)) end

local function pick_proj_then(prompt, fn)
  picker.project({ prompt = prompt }, function(proj)
    if proj then fn(proj) end
  end)
end

local function ef(proj, args, label)
  local proj_dir = vim.fn.fnamemodify(proj, ":h")
  local cmd_args = vim.list_extend({ "dotnet", "ef" }, args)
  vim.list_extend(cmd_args, { "--project", proj })
  runner.bg(cmd_args, { cwd = proj_dir, label = label })
end

-- ── Migrations ───────────────────────────────────────────────────────────────

reg("ef.migration.add", {
  icon = " ",
  desc = "EF: Add migration",
  run  = function()
    pick_proj_then("Add migration to project:", function(proj)
      vim.ui.input({ prompt = "Migration name: " }, function(name)
        if name and name ~= "" then
          ef(proj, { "migrations", "add", name }, "EF add migration: " .. name)
        end
      end)
    end)
  end,
})

reg("ef.migration.remove", {
  icon = " ",
  desc = "EF: Remove last migration",
  run  = function()
    pick_proj_then("Remove last migration from:", function(proj)
      ef(proj, { "migrations", "remove" }, "EF remove migration")
    end)
  end,
})

reg("ef.migration.list", {
  icon = " ",
  desc = "EF: List migrations",
  run  = function()
    pick_proj_then("List migrations for:", function(proj)
      ef(proj, { "migrations", "list" }, "EF list migrations")
    end)
  end,
})

reg("ef.migration.script", {
  icon = " ",
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
    pick_proj_then("Update database for:", function(proj)
      ef(proj, { "database", "update" }, "EF database update")
    end)
  end,
})

reg("ef.db.update_to", {
  icon = "󰆑 ",
  desc = "EF: Update database to migration",
  run  = function()
    pick_proj_then("Update database to migration:", function(proj)
      vim.ui.input({ prompt = "Target migration (or '0' to revert all): " }, function(target)
        if target and target ~= "" then
          ef(proj, { "database", "update", target }, "EF database update → " .. target)
        end
      end)
    end)
  end,
})

reg("ef.db.drop", {
  icon = "󰆑 ",
  desc = "EF: Drop database",
  run  = function()
    pick_proj_then("Drop database for:", function(proj)
      vim.ui.select({ "Yes, drop it", "Cancel" }, { prompt = "Drop database? This is irreversible!" }, function(choice)
        if choice and choice:match("^Yes") then
          ef(proj, { "database", "drop", "--force" }, "EF database drop")
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
