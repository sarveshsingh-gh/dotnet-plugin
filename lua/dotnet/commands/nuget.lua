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
  local ok, props = pcall(require("dotnet.core.project").deps, proj_path)
  local pkgs = (ok and props and props.pkgs) or {}
  if #pkgs == 0 then
    require("dotnet.notify").info("No packages found in project")
    return
  end
  vim.ui.select(pkgs, {
    prompt      = "Remove package:",
    format_item = function(p) return p.name .. "  " .. p.version end,
  }, function(choice)
    if not choice then return end
    runner.bg({ "dotnet", "remove", "package", choice.name }, {
      cwd      = vim.fn.fnamemodify(proj_path, ":h"),
      label    = "NuGet remove " .. choice.name,
      on_exit  = function() pcall(function() require("dotnet.ui.explorer").refresh_if_open() end) end,
    })
  end)
end

local function do_list_packages(proj_path)
  local ok_p,  pickers   = pcall(require, "telescope.pickers")
  local ok_f,  finders   = pcall(require, "telescope.finders")
  local ok_c,  conf      = pcall(require, "telescope.config")
  local ok_a,  actions   = pcall(require, "telescope.actions")
  local ok_as, act_state = pcall(require, "telescope.actions.state")
  if not (ok_p and ok_f and ok_c and ok_a and ok_as) then return end

  local ok_proj, props = pcall(require("dotnet.core.project").deps, proj_path)
  local pkgs = (ok_proj and props and props.pkgs) or {}
  if #pkgs == 0 then
    require("dotnet.notify").info("No packages in project")
    return
  end

  local cwd = vim.fn.fnamemodify(proj_path, ":h")

  local function explorer_refresh()
    pcall(function() require("dotnet.ui.explorer").refresh_if_open() end)
  end

  local function remove(sel)
    runner.bg({ "dotnet", "remove", "package", sel.name }, {
      cwd     = cwd,
      label   = "NuGet remove " .. sel.name,
      on_exit = function() explorer_refresh() end,
    })
  end

  local function upgrade(sel)
    runner.bg({ "dotnet", "add", "package", sel.name }, {
      cwd     = cwd,
      label   = "NuGet upgrade " .. sel.name,
      on_exit = function() explorer_refresh() end,
    })
  end

  pickers.new({}, {
    prompt_title = "NuGet Packages  <CR> remove · <C-u> upgrade",
    finder = finders.new_table({
      results = pkgs,
      entry_maker = function(p)
        return {
          value   = p,
          display = string.format("%-48s %s", p.name, p.version),
          ordinal = p.name,
        }
      end,
    }),
    sorter = conf.values.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local sel = act_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if sel then remove(sel.value) end
      end)

      local function do_upgrade()
        local sel = act_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if sel then upgrade(sel.value) end
      end
      map("i", "<C-u>", do_upgrade)
      map("n", "<C-u>", do_upgrade)

      return true
    end,
  }):find()
end

local function do_outdated(proj_path)
  local cwd = vim.fn.fnamemodify(proj_path, ":h")
  require("dotnet.notify").info("Checking for outdated packages…")
  runner.bg({ "dotnet", "list", "package", "--outdated" }, {
    cwd          = cwd,
    label        = "NuGet outdated",
    notify_success = false,
    on_exit = function(_, stdout, stderr)
      -- parse lines like:  > PackageName   requested   resolved   latest
      local pkgs = {}
      local lines = vim.list_extend(vim.deepcopy(stdout or {}), stderr or {})
      for _, l in ipairs(lines) do
        local name, cur, latest = l:match("^%s*>%s+(%S+)%s+%S+%s+(%S+)%s+(%S+)")
        if name then
          table.insert(pkgs, { name = name, version = cur, latest = latest })
        end
      end

      if #pkgs == 0 then
        require("dotnet.notify").info("All packages are up to date")
        return
      end

      local ok_p,  pickers   = pcall(require, "telescope.pickers")
      local ok_f,  finders   = pcall(require, "telescope.finders")
      local ok_c,  conf      = pcall(require, "telescope.config")
      local ok_a,  actions   = pcall(require, "telescope.actions")
      local ok_as, act_state = pcall(require, "telescope.actions.state")
      if not (ok_p and ok_f and ok_c and ok_a and ok_as) then return end

      local function exp_refresh()
        pcall(function() require("dotnet.ui.explorer").refresh_if_open() end)
      end

      local function upgrade(p)
        runner.bg({ "dotnet", "add", "package", p.name, "--version", p.latest }, {
          cwd     = cwd,
          label   = "NuGet upgrade " .. p.name .. " → " .. p.latest,
          on_exit = function() exp_refresh() end,
        })
      end

      local function remove(p)
        runner.bg({ "dotnet", "remove", "package", p.name }, {
          cwd     = cwd,
          label   = "NuGet remove " .. p.name,
          on_exit = function() exp_refresh() end,
        })
      end

      vim.schedule(function()
        pickers.new({}, {
          prompt_title = "Outdated Packages  <CR> upgrade · <C-d> remove",
          finder = finders.new_table({
            results = pkgs,
            entry_maker = function(p)
              return {
                value   = p,
                display = string.format("%-45s %-18s → %s", p.name, p.version, p.latest),
                ordinal = p.name,
              }
            end,
          }),
          sorter = conf.values.generic_sorter({}),
          attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
              local sel = act_state.get_selected_entry()
              actions.close(prompt_bufnr)
              if sel then upgrade(sel.value) end
            end)

            local function do_remove()
              local sel = act_state.get_selected_entry()
              actions.close(prompt_bufnr)
              if sel then remove(sel.value) end
            end
            map("i", "<C-d>", do_remove)
            map("n", "<C-d>", do_remove)

            return true
          end,
        }):find()
      end)
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
