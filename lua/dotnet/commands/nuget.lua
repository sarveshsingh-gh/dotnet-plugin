-- dotnet.nvim — NuGet commands
local cmd    = require("dotnet.commands.init")
local runner = require("dotnet.core.runner")
local picker = require("dotnet.ui.picker")

-- Percent-encode a string for use in URLs
local function url_encode(s)
  return (s:gsub("[^%w%-_%.~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

-- Search NuGet.org via the nuget search API (no auth required)
local function search_packages(query, cb)
  local url = "https://azuresearch-usnc.nuget.org/query?q="
    .. url_encode(query) .. "&take=50&prerelease=false"

  local buf = {}
  vim.fn.jobstart({ "curl", "-sf", url }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then table.insert(buf, line) end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        require("dotnet.notify").warn("NuGet search failed")
        return cb({})
      end
      local ok, decoded = pcall(vim.json.decode, table.concat(buf))
      if not ok or not decoded or not decoded.data then
        return cb({})
      end
      local results = {}
      for _, pkg in ipairs(decoded.data) do
        table.insert(results, {
          id      = pkg.id,
          version = pkg.version,
          desc    = pkg.description or "",
          total   = pkg.totalDownloads or 0,
        })
      end
      cb(results)
    end,
  })
end

-- Word-wrap text to fit within `width` columns
local function wrap(text, width)
  local lines = {}
  text = text:gsub("[\r\n]+", " "):gsub("%s+", " ")
  while #text > width do
    local cut = text:sub(1, width):match("^(.-)%s*$") -- trim trailing space
    local space = cut:match(".*()%s") or width         -- last space position
    table.insert(lines, text:sub(1, space - 1))
    text = text:sub(space + 1)
  end
  if #text > 0 then table.insert(lines, text) end
  return lines
end

local function do_add_package(proj_path)
  local ok_p,  pickers    = pcall(require, "telescope.pickers")
  local ok_f,  finders    = pcall(require, "telescope.finders")
  local ok_c,  conf       = pcall(require, "telescope.config")
  local ok_a,  actions    = pcall(require, "telescope.actions")
  local ok_as, act_state  = pcall(require, "telescope.actions.state")
  local ok_pr, previewers = pcall(require, "telescope.previewers")
  if not (ok_p and ok_f and ok_c and ok_a and ok_as and ok_pr) then
    require("dotnet.notify").warn("telescope.nvim is required for NuGet search")
    return
  end

  local cache       = {}
  local last_job    = nil
  local debounce_id = nil
  local the_picker  = nil

  local function make_entry(p)
    return {
      value   = p,
      display = string.format("%-45s %s", p.id, p.version),
      ordinal = p.id .. " " .. (p.desc or ""),
    }
  end

  -- Preview pane: render full package metadata
  local nuget_previewer = previewers.new_buffer_previewer({
    title = "Package Info",
    define_preview = function(self, entry)
      if not entry or not entry.value then return end
      local p   = entry.value
      local win = self.state.winid
      local w   = win and (vim.api.nvim_win_get_width(win) - 4) or 60

      local dl = p.total or 0
      local dl_fmt = tostring(dl):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")

      local lines = {
        "  " .. (p.id or ""),
        "",
        ("  %-14s %s"):format("Version",   p.version or ""),
        ("  %-14s %s"):format("Downloads", dl_fmt),
      }
      if p.authors and #p.authors > 0 then
        table.insert(lines, ("  %-14s %s"):format("Authors", table.concat(p.authors, ", ")))
      end
      if p.url and p.url ~= "" then
        table.insert(lines, ("  %-14s %s"):format("URL", p.url))
      end
      if p.tags and #p.tags > 0 then
        table.insert(lines, ("  %-14s %s"):format("Tags", table.concat(p.tags, ", ")))
      end
      table.insert(lines, "")
      table.insert(lines, "  Description")
      table.insert(lines, "  " .. string.rep("─", math.max(w - 2, 4)))
      for _, l in ipairs(wrap(p.desc or "No description.", w - 2)) do
        table.insert(lines, "  " .. l)
      end

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      vim.bo[self.state.bufnr].filetype = "markdown"
    end,
  })

  local function refresh(results)
    vim.schedule(function()
      if not the_picker then return end
      the_picker:refresh(finders.new_table({
        results     = results,
        entry_maker = make_entry,
      }), { reset_prompt = false })
    end)
  end

  local function search(query)
    if not query or #query < 2 then return end
    if cache[query] then refresh(cache[query]); return end
    if last_job then pcall(vim.fn.jobstop, last_job); last_job = nil end
    local url = "https://azuresearch-usnc.nuget.org/query?q="
      .. url_encode(query) .. "&take=30&prerelease=false"
    local buf = {}
    last_job = vim.fn.jobstart({ "curl", "-sf", url }, {
      stdout_buffered = true,
      on_stdout = function(_, data)
        for _, line in ipairs(data) do
          if line ~= "" then table.insert(buf, line) end
        end
      end,
      on_exit = function(_, code)
        last_job = nil
        local results = {}
        if code == 0 then
          local ok_j, decoded = pcall(vim.json.decode, table.concat(buf))
          if ok_j and decoded and decoded.data then
            for _, pkg in ipairs(decoded.data) do
              local authors = {}
              for _, a in ipairs(pkg.authors or {}) do table.insert(authors, a) end
              local tags = {}
              for _, t in ipairs(pkg.tags or {}) do table.insert(tags, t) end
              table.insert(results, {
                id      = pkg.id,
                version = pkg.version,
                desc    = pkg.description or "",
                total   = pkg.totalDownloads or 0,
                authors = authors,
                tags    = tags,
                url     = pkg.projectUrl or "",
              })
            end
          end
        end
        cache[query] = results
        refresh(results)
      end,
    })
  end

  -- Debounce: fire search 300 ms after the user stops typing
  local function search_debounced(query)
    if debounce_id then vim.fn.timer_stop(debounce_id); debounce_id = nil end
    debounce_id = vim.fn.timer_start(300, function()
      debounce_id = nil
      search(query)
    end)
  end

  the_picker = pickers.new({}, {
    prompt_title  = "Add NuGet Package",
    finder        = finders.new_table({ results = {}, entry_maker = make_entry }),
    sorter        = conf.values.generic_sorter({}),
    previewer     = nuget_previewer,
    layout_strategy = "vertical",
    layout_config   = {
      vertical = {
        preview_height = 0.45,   -- 45 % of window height for description
        results_height = 0.45,
        prompt_position = "top",
        mirror = false,
      },
      width  = 0.95,
      height = 0.90,
    },
    attach_mappings = function(prompt_bufnr)
      vim.api.nvim_buf_attach(prompt_bufnr, false, {
        on_lines = function()
          vim.schedule(function()
            search_debounced(act_state.get_current_line())
          end)
        end,
      })
      actions.select_default:replace(function()
        local sel = act_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if sel then
          local pkg = sel.value
          runner.bg({ "dotnet", "add", "package", pkg.id, "--version", pkg.version }, {
            cwd    = vim.fn.fnamemodify(proj_path, ":h"),
            label  = "NuGet add " .. pkg.id,
            notify = true,
          })
        end
      end)
      return true
    end,
  })
  the_picker:find()
end

local function do_remove_package(proj_path)
  -- Read current packages from csproj
  local ok, props = pcall(require("dotnet.core.project").deps, proj_path)
  local pkgs = (ok and props and props.pkgs) or {}
  if #pkgs == 0 then
    require("dotnet.notify").info("No packages found in project")
    return
  end
  vim.ui.select(pkgs, { prompt = "Remove package:" }, function(choice)
    if not choice then return end
    runner.bg({ "dotnet", "remove", "package", choice }, {
      cwd   = vim.fn.fnamemodify(proj_path, ":h"),
      label = "NuGet remove " .. choice,
      notify = true,
    })
  end)
end

local function do_list_packages(proj_path)
  local cwd = vim.fn.fnamemodify(proj_path, ":h")
  runner.bg({ "dotnet", "list", "package" }, {
    cwd   = cwd,
    label = "NuGet list",
    on_exit = function(lines)
      local result = {}
      for _, l in ipairs(lines) do
        if l:match("^%s*>") then
          table.insert(result, vim.trim(l))
        end
      end
      if #result == 0 then
        require("dotnet.notify").info("No packages")
      else
        vim.schedule(function()
          require("dotnet.notify").info("Packages:\n" .. table.concat(result, "\n"))
        end)
      end
    end,
  })
end

local function do_outdated(proj_path)
  local cwd = vim.fn.fnamemodify(proj_path, ":h")
  runner.bg({ "dotnet", "list", "package", "--outdated" }, {
    cwd   = cwd,
    label = "NuGet outdated",
    on_exit = function(lines)
      local result = {}
      for _, l in ipairs(lines) do
        if l:match("^%s*>") then
          table.insert(result, vim.trim(l))
        end
      end
      if #result == 0 then
        require("dotnet.notify").info("All packages up to date")
      else
        vim.schedule(function()
          local msg = table.concat(result, "\n")
          require("dotnet.notify").warn("Outdated packages:\n" .. msg)
        end)
      end
    end,
  })
end

-- Register commands
cmd.register("nuget.add", {
  category = "nuget",
  icon     = "󰐗 ",
  desc     = "Add NuGet package",
  run      = function()
    picker.project({}, function(proj)
      do_add_package(proj)
    end)
  end,
})

cmd.register("nuget.remove", {
  category = "nuget",
  icon     = "󰐘 ",
  desc     = "Remove NuGet package",
  run      = function()
    picker.project({}, function(proj)
      do_remove_package(proj)
    end)
  end,
})

cmd.register("nuget.list", {
  category = "nuget",
  icon     = "󰒕 ",
  desc     = "List NuGet packages",
  run      = function()
    picker.project({}, function(proj)
      do_list_packages(proj)
    end)
  end,
})

cmd.register("nuget.outdated", {
  category = "nuget",
  icon     = "󰏗 ",
  desc     = "List outdated packages",
  run      = function()
    picker.project({}, function(proj)
      do_outdated(proj)
    end)
  end,
})

local M = {}
M.add_package     = do_add_package
M.remove_package  = do_remove_package
M.list_packages   = do_list_packages
M.outdated        = do_outdated
return M
