-- nvim-cmp source: NuGet completions inside .csproj / .props / .targets
--
-- Triggers on:
--   <PackageReference Include="|"        → live NuGet package search
--   <PackageReference Include="Foo" Version="|"  → all versions for Foo

local source = {}

source.new = function()
  return setmetatable({ _pkg_cache = {}, _ver_cache = {} }, { __index = source })
end

source.get_debug_name = function() return "nuget" end

source.is_available = function()
  local name = vim.api.nvim_buf_get_name(0)
  return name:match("%.[cf]sproj$") ~= nil
      or name:match("%.props$")     ~= nil
      or name:match("%.targets$")   ~= nil
end

source.get_trigger_characters = function() return { '"', "." } end

-- Returns "package", pkg_query  OR  "version", pkg_name, ver_query  OR nil
local function detect_context(before_cursor)
  -- Version="|"  (package name must appear earlier on the same line)
  local pkg_name  = before_cursor:match('Include="([^"]+)"')
  local ver_query = before_cursor:match('Version="([^"]*)')
  if ver_query ~= nil and pkg_name then
    return "version", pkg_name, ver_query
  end

  -- Include="|"
  local pkg_query = before_cursor:match('Include="([^"]*)')
  if pkg_query ~= nil then
    return "package", nil, pkg_query
  end

  return nil
end

local function url_encode(s)
  return (s:gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

local function fetch(url, on_done)
  local buf = {}
  vim.fn.jobstart({ "curl", "-sf", "--max-time", "5", url }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      for _, l in ipairs(data) do if l ~= "" then table.insert(buf, l) end end
    end,
    on_exit = function(_, code)
      if code ~= 0 then return on_done(nil) end
      local ok, decoded = pcall(vim.json.decode, table.concat(buf))
      on_done(ok and decoded or nil)
    end,
  })
end

function source:_search_packages(query, callback)
  if self._pkg_cache[query] then return callback(self._pkg_cache[query]) end
  local url = "https://azuresearch-usnc.nuget.org/query?q="
    .. url_encode(query) .. "&take=25&prerelease=false"
  fetch(url, function(data)
    if not data or not data.data then return callback({}) end
    local items = {}
    for _, pkg in ipairs(data.data) do
      local dl = pkg.totalDownloads or 0
      local dl_fmt = tostring(dl):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
      table.insert(items, {
        label         = pkg.id,
        detail        = pkg.version .. "  ↓" .. dl_fmt,
        documentation = { kind = "plaintext", value = pkg.description or "" },
        insertText    = pkg.id,
        kind          = 9,  -- Module
      })
    end
    self._pkg_cache[query] = items
    callback(items)
  end)
end

function source:_fetch_versions(pkg_id, callback)
  local key = pkg_id:lower()
  if self._ver_cache[key] then return callback(self._ver_cache[key]) end
  local url = "https://api.nuget.org/v3-flatcontainer/" .. key .. "/index.json"
  fetch(url, function(data)
    if not data or not data.versions then return callback({}) end
    local items = {}
    -- newest first
    for i = #data.versions, 1, -1 do
      table.insert(items, {
        label      = data.versions[i],
        insertText = data.versions[i],
        kind       = 12,  -- Value
      })
    end
    self._ver_cache[key] = items
    callback(items)
  end)
end

function source:complete(params, callback)
  local before = params.context.cursor_before_line
  local ctx, pkg_name, query = detect_context(before)

  if not ctx then
    return callback({ items = {}, isIncomplete = false })
  end

  if ctx == "version" and pkg_name and pkg_name ~= "" then
    self:_fetch_versions(pkg_name, function(items)
      vim.schedule(function() callback({ items = items, isIncomplete = false }) end)
    end)
  elseif ctx == "package" then
    if not query or #query < 2 then
      return callback({ items = {}, isIncomplete = true })
    end
    self:_search_packages(query, function(items)
      vim.schedule(function() callback({ items = items, isIncomplete = true }) end)
    end)
  else
    callback({ items = {}, isIncomplete = false })
  end
end

return source
