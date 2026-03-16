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
    vim.notify("[dotnet] Unknown command: " .. id, vim.log.levels.ERROR)
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

return M
