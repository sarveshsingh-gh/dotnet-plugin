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
    ["build.solution"]     = km.build_solution,
    ["build.quickfix"]     = km.build_quickfix,
    ["build.restore"]      = km.restore,
    ["build.clean"]        = km.clean,
    ["build.rebuild"]      = km.rebuild,
    ["run.project"]        = km.run_project,
    ["run.watch"]          = km.watch,
    ["run.stop_all"]       = km.stop_all,
    ["test.solution"]      = km.test_solution,
    ["test.project"]       = km.test_project,
    ["file.new_item"]      = km.new_item,
    ["file.fix_namespace"] = km.fix_namespace,
    ["explorer.toggle"]    = km.explorer_toggle,
    ["explorer.reveal"]    = km.explorer_reveal,
    ["test_explorer.toggle"] = km.test_explorer,
    ["jobs.list"]          = km.list_jobs,
    ["nuget.add"]          = km.nuget_add,
    ["nuget.remove"]       = km.nuget_remove,
  }
  for id, key in pairs(map) do
    if _registry[id] and key then _registry[id].key = key end
  end
end

return M
