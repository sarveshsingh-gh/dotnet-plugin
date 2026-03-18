-- Central command registry.
-- Every feature registers commands here so the palette can list them all.
--
-- Command definition:
--   id       : string  — unique key  e.g. "build.solution"
--   desc     : string  — shown in palette
--   category : string  — "build"|"run"|"test"|"solution"|"project"|"file"|"debug"|"nuget"
--   icon     : string  — optional icon prefix
--   run      : fn()    — executed when selected
--   context  : list    — optional {"solution","project","file"} narrows palette context

local M = {}
local _registry = {}   -- id → definition

-- Filetypes used by common dashboard plugins
local DASH_FT = { nvdash = true, alpha = true, dashboard = true, starter = true }

local function close_dashboard()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if DASH_FT[vim.bo[buf].filetype] then
      vim.api.nvim_win_call(win, function() vim.cmd("enew") end)
    end
  end
end

M.close_dashboard = close_dashboard

function M.register(id, def)
  assert(def.desc and def.run, "dotnet command '" .. id .. "' needs desc + run")
  _registry[id] = vim.tbl_extend("keep", def, { id = id, icon = def.icon or "" })
end

function M.run(id, ...)
  local def = _registry[id]
  if not def then
    require("dotnet.notify").error("Unknown command: " .. id)
    return
  end
  close_dashboard()
  def.run(...)
end

--- All registered commands as a list (sorted by category then desc).
function M.all()
  local list = vim.tbl_values(_registry)
  table.sort(list, function(a, b)
    if a.category ~= b.category then return (a.category or "") < (b.category or "") end
    return a.desc < b.desc
  end)
  return list
end

--- Commands matching a category filter.
function M.for_category(cat)
  return vim.tbl_filter(function(c) return c.category == cat end, M.all())
end

function M.get(id) return _registry[id] end

--- Annotate commands with their keybindings from the resolved config keymaps.
function M.annotate_keys(km)
  local map = {
    -- build
    ["build.solution"]       = km.build_solution,
    ["build.quickfix"]       = km.build_quickfix,
    ["build.restore"]        = km.restore,
    ["build.clean"]          = km.clean,
    ["build.rebuild"]        = km.rebuild,
    -- run
    ["run.project"]          = km.run_project,
    ["run.watch"]            = km.watch,
    ["run.stop_all"]         = km.stop_all,
    -- test
    ["test.solution"]        = km.test_solution,
    ["test.project"]         = km.test_project,
    -- file
    ["file.new_item"]        = km.new_item,
    ["file.fix_namespace"]   = km.fix_namespace,
    ["files.find"]           = km.find_file,
    -- explorer
    ["explorer.toggle"]      = km.explorer_toggle,
    ["explorer.reveal"]      = km.explorer_reveal,
    ["test_explorer.toggle"] = km.test_explorer,  -- <leader>te
    -- run (extra)
    ["run.profile"]          = km.run_profile,
    ["run.func"]             = km.run_func,
    ["run.func_debug"]       = km.debug_func,
    -- file (extra)
    ["file.launch_settings"] = km.launch_settings,
    -- misc
    ["jobs.list"]            = km.list_jobs,
    ["nuget.add"]            = km.nuget_add,
    ["nuget.remove"]         = km.nuget_remove,
    ["nuget.list"]           = km.nuget_list,
    ["nuget.outdated"]       = km.nuget_outdated,
    -- EF Core
    ["ef.migration.add"]     = km.ef_migration_add,
    ["ef.migration.remove"]  = km.ef_migration_remove,
    ["ef.migration.list"]    = km.ef_migration_list,
    ["ef.migration.script"]  = km.ef_migration_script,
    ["ef.db.update"]         = km.ef_db_update,
    ["ef.db.update_to"]      = km.ef_db_update_to,
    ["ef.db.drop"]           = km.ef_db_drop,
    ["ef.scaffold"]          = km.ef_scaffold,
    -- debug
    ["debug.launch"]         = km.debug_launch,
    -- debug F-keys (hardcoded — set in keymaps.lua)
    ["debug.continue"]       = "<F5>",
    ["debug.stop"]           = "<S-F5>",
    ["debug.step_over"]      = "<F10>",
    ["debug.step_into"]      = "<F11>",
    ["debug.step_out"]       = "<S-F11>",
    ["debug.breakpoint"]     = "<F9>",
    ["debug.eval"]           = "<S-F9>",
  }
  for id, key in pairs(map) do
    if _registry[id] and key then _registry[id].key = key end
  end
end

return M
