-- Solution Explorer — VS Code style panel.
-- Depends on: core/solution, core/project, core/runner, core/namespace,
--             commands/file, telescope/files, ui/picker
local M = {}

local solution  = require("dotnet.core.solution")
local project   = require("dotnet.core.project")
local runner    = require("dotnet.core.runner")
local namespace = require("dotnet.core.namespace")

-- ── State ─────────────────────────────────────────────────────────────────────

local S = {
  buf         = nil,
  win         = nil,
  sln_path    = nil,
  nodes       = {},     -- flat rendered list
  collapsed   = {},     -- path → bool
  show_hidden = false,
}

-- ── Icons ─────────────────────────────────────────────────────────────────────

local function g(cp) return vim.fn.nr2char(cp, 1) end

local ARROW_OPEN  = "▼ "
local ARROW_CLOSE = "▶ "
local LEAF_PAD    = "  "
local INDENT      = "  "

local _dv = nil
local function dv()
  if _dv == nil then
    local ok, m = pcall(require, "nvim-web-devicons")
    _dv = ok and m or false
  end
  return _dv
end

local function icon_for_file(name)
  local d = dv()
  if d then
    local ext      = name:match("%.([^./]+)$") or ""
    local ic, hl   = d.get_icon(name, ext, { default = true })
    if ic and ic ~= "" then return ic .. " ", hl end
  end
  return g(0xF15B) .. " ", nil
end

local function folder_icon(collapsed)
  local ok, mi = pcall(require, "mini.icons")
  if ok then
    local ic, hl = mi.get("directory", "")
    if ic and ic ~= "" then
      return ic .. " ", hl
    end
  end
  return (collapsed and g(0xE5FF) or g(0xE5FE)) .. " ", "Directory"
end

local function sln_icon()
  local d = dv()
  if d then local ic = d.get_icon("solution.sln", "sln", { default = true }); if ic then return ic .. " " end end
  return g(0xF0E8) .. " "
end

local function proj_icon_for(proj_path)
  local kind = project.kind(proj_path)
  local d = dv()
  local function di(name, ext)
    if d then local ic = d.get_icon(name, ext, { default = true }); if ic then return ic .. " " end end
  end
  if kind == "web"     then return di("api.csproj",     "csproj") or g(0xF1B2) .. " " end
  if kind == "console" then return di("console.csproj", "csproj") or g(0xF489) .. " " end
  if kind == "test"    then return di("test.csproj",    "csproj") or g(0xF0AD) .. " " end
  return di("lib.csproj", "csproj") or g(0xF1B2) .. " "
end

local I = {
  deps    = g(0xF487) .. " ",
  pkg     = g(0xF487) .. " ",
  projref = g(0xF0E8) .. " ",
}

-- ── Highlight namespace ────────────────────────────────────────────────────────

local HL_NS = vim.api.nvim_create_namespace("dotnet_explorer")

vim.api.nvim_set_hl(0, "DotnetSlnProject", { link = "Directory" })
vim.api.nvim_set_hl(0, "DotnetSlnFolder",  { link = "Directory" })

local KIND_HL = {
  solution = "Title",
  project  = "DotnetSlnProject",
  dir      = "DotnetSlnFolder",
  file     = "Normal",
  deps     = "DotnetSlnFolder",
  pkg      = "String",
  projref  = "Type",
}

-- ── Forward declarations ───────────────────────────────────────────────────────

local HEADER_OFFSET = 2   -- "  Solution Explorer" + separator

local refresh        -- defined below
local action_open_file  -- defined below

-- ── Build node tree ────────────────────────────────────────────────────────────

local function build_nodes()
  local nodes = {}
  local sln   = S.sln_path
  if not sln then return nodes end

  local proj_list = solution.projects(sln)

  for _, proj_path in ipairs(proj_list) do
    local proj_name = vim.fn.fnamemodify(proj_path, ":t:r")
    local proj_dir  = vim.fn.fnamemodify(proj_path, ":h")
    local is_coll   = S.collapsed[proj_path] or false
    local pio       = proj_icon_for(proj_path)

    table.insert(nodes, {
      text      = pio .. proj_name,
      indent    = 1, kind = "project", path = proj_path, dir = proj_dir,
      collapsed = is_coll,
      _ibytes   = #pio, _ihl = nil,
    })

    if not is_coll then
      -- Dependencies node
      local deps_path = proj_path .. "::deps"
      if S.collapsed[deps_path] == nil then S.collapsed[deps_path] = true end
      local deps_coll = S.collapsed[deps_path]
      local deps_data = project.deps(proj_path)
      local n_deps    = #deps_data.pkgs + #deps_data.refs

      if n_deps > 0 then
        table.insert(nodes, {
          text      = I.deps .. "Dependencies",
          text_sfx  = "  · " .. n_deps,
          indent    = 2, kind = "deps", path = deps_path,
          collapsed = deps_coll,
          _ibytes   = #I.deps, _ihl = nil,
        })

        if not deps_coll then
          for _, pr in ipairs(deps_data.refs) do
            table.insert(nodes, {
              text       = I.projref .. pr.name,
              indent     = 3, kind = "projref",
              path       = proj_path .. "::projref::" .. pr.name,
              collapsed  = false,
              _ibytes    = #I.projref, _ihl = nil,
              _proj_path = proj_path, _ref_path = pr.path,
            })
          end
          for _, pk in ipairs(deps_data.pkgs) do
            table.insert(nodes, {
              text      = I.pkg .. pk.name,
              text_sfx  = pk.version ~= "" and ("  " .. pk.version) or nil,
              indent    = 3, kind = "pkg",
              path      = proj_path .. "::pkg::" .. pk.name,
              collapsed = false,
              _ibytes   = #I.pkg, _ihl = nil,
              _proj_path = proj_path, _pkg_name = pk.name,
            })
          end
        end
      end

      -- File tree
      for _, e in ipairs(project.scan_dir(proj_dir, S.show_hidden)) do
        if e.is_dir then
          local fic, fhl = folder_icon(S.collapsed[e.path])
          table.insert(nodes, {
            text      = fic .. e.name,
            indent    = 2 + e.depth, kind = "dir", path = e.path,
            collapsed = S.collapsed[e.path] or false,
            _ibytes   = #fic, _ihl = fhl,
          })
        else
          local fic, fhl = icon_for_file(e.name)
          table.insert(nodes, {
            text      = fic .. e.name,
            indent    = 2 + e.depth, kind = "file", path = e.path,
            collapsed = false,
            _ibytes   = #fic, _ihl = fhl,
          })
        end
      end
    end
  end

  return nodes
end

-- ── Render ─────────────────────────────────────────────────────────────────────

local function render()
  if not S.buf or not vim.api.nvim_buf_is_valid(S.buf) then return end
  local lines = { "  Solution Explorer", string.rep("─", 30) }
  for _, n in ipairs(S.nodes) do
    local ind    = INDENT:rep(n.indent)
    local is_leaf = n.kind == "file" or n.kind == "pkg" or n.kind == "projref"
    local arrow  = is_leaf and LEAF_PAD or (n.collapsed and ARROW_CLOSE or ARROW_OPEN)
    local line   = ind .. arrow .. n.text .. (n.text_sfx or "")
    table.insert(lines, line)
    n._pfx      = #ind + #arrow
    n._name_end = #line - #(n.text_sfx or "")
  end

  vim.bo[S.buf].modifiable = true
  vim.api.nvim_buf_set_lines(S.buf, 0, -1, false, lines)
  vim.bo[S.buf].modifiable = false

  -- Highlights
  vim.api.nvim_buf_clear_namespace(S.buf, HL_NS, 0, -1)
  vim.api.nvim_buf_add_highlight(S.buf, HL_NS, "Title", 0, 0, -1)
  for idx, n in ipairs(S.nodes) do
    local row = idx - 1 + HEADER_OFFSET  -- 0-based screen row
    local hl = KIND_HL[n.kind] or "Normal"
    vim.api.nvim_buf_set_extmark(S.buf, HL_NS, row, n._pfx, {
      end_col   = n._name_end,
      hl_group  = hl,
      priority  = 200,
    })
    if n._ihl and n._ibytes > 0 then
      vim.api.nvim_buf_set_extmark(S.buf, HL_NS, row, n._pfx, {
        end_col  = n._pfx + n._ibytes,
        hl_group = n._ihl,
        priority = 300,
      })
    end
    -- Dim text_sfx
    if n.text_sfx then
      vim.api.nvim_buf_set_extmark(S.buf, HL_NS, row, n._name_end, {
        end_col  = #lines[idx + HEADER_OFFSET],
        hl_group = "Comment",
        priority = 200,
      })
    end
  end
end

refresh = function()
  S.nodes = build_nodes()
  render()
end

-- ── Helpers ────────────────────────────────────────────────────────────────────

local function current_node()
  if not S.win or not vim.api.nvim_win_is_valid(S.win) then return nil end
  local row = vim.api.nvim_win_get_cursor(S.win)[1]
  local idx = row - HEADER_OFFSET
  return S.nodes[idx], idx
end

local function nearest_project(from_row)
  for i = from_row, 1, -1 do
    local n = S.nodes[i]
    if n and n.kind == "project" then return n end
  end
end

local function panel_width()
  local cfg = (require("dotnet").config() or {}).explorer or {}
  return math.max(cfg.min_width or 30, math.floor(vim.o.columns * (cfg.width or 0.18)))
end

local function confirm(msg, cb)
  vim.ui.input({ prompt = msg .. " [y/N]: " }, function(ans)
    if ans and ans:lower() == "y" then cb() end
  end)
end

-- ── Actions ────────────────────────────────────────────────────────────────────

action_open_file = function(node)
  local target
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= S.win then
      local bt = vim.bo[vim.api.nvim_win_get_buf(w)].buftype
      if bt == "" or bt == "acwrite" then target = w; break end
    end
  end
  if not target then
    vim.cmd("botright vsplit")
    target = vim.api.nvim_get_current_win()
    if S.win and vim.api.nvim_win_is_valid(S.win) then
      vim.api.nvim_set_current_win(S.win)
    end
  end
  vim.api.nvim_win_call(target, function()
    vim.cmd("edit " .. vim.fn.fnameescape(node.path))
  end)
end

local function action_toggle_fold(node)
  S.collapsed[node.path] = not S.collapsed[node.path]
  local row = vim.api.nvim_win_get_cursor(S.win)[1]
  refresh()
  pcall(vim.api.nvim_win_set_cursor, S.win, { row, 0 })
end

local function action_new_item(proj_node, target_dir)
  -- Delegate to commands/file which has the full template list
  require("dotnet.commands.file")   -- ensure loaded
  local cmd_file = require("dotnet.commands.init")
  -- call do_new_item exposed by commands/file
  local ok, file_cmd = pcall(require, "dotnet.commands.file_api")
  -- simpler: just inline the call
  local namespace_m = namespace
  local picker      = require("dotnet.ui.picker")
  local TEMPLATES = {
    { value = "class",          display = "Class",                    ext = ".cs"     },
    { value = "interface",      display = "Interface",                ext = ".cs"     },
    { value = "record",         display = "Record",                   ext = ".cs"     },
    { value = "struct",         display = "Struct",                   ext = ".cs"     },
    { value = "enum",           display = "Enum",                     ext = ".cs"     },
    { value = "apicontroller",  display = "API Controller",           ext = ".cs"     },
    { value = "mvccontroller",  display = "MVC Controller",           ext = ".cs"     },
    { value = "razorcomponent", display = "Razor Component",          ext = ".razor"  },
    { value = "page",           display = "Razor Page",               ext = ".cshtml" },
    { value = "view",           display = "Razor View",               ext = ".cshtml" },
    { value = "nunit-test",     display = "NUnit Test",               ext = ".cs"     },
    { value = "buildprops",     display = "Directory.Build.props",    predefined = "Directory.Build.props"     },
    { value = "packagesprops",  display = "Directory.Packages.props", predefined = "Directory.Packages.props"  },
    { value = "gitignore",      display = ".gitignore",               predefined = ".gitignore"    },
    { value = "editorconfig",   display = ".editorconfig",            predefined = ".editorconfig" },
    { value = "globaljson",     display = "global.json",              predefined = "global.json"   },
    { value = "nugetconfig",    display = "nuget.config",             predefined = "nuget.config"  },
  }
  local proj_dir = vim.fn.fnamemodify(proj_node.path, ":h")
  local out_dir  = target_dir or proj_dir

  vim.ui.select(TEMPLATES, {
    prompt      = "New item (" .. vim.fn.fnamemodify(proj_node.path, ":t:r") .. "):",
    format_item = function(t) return t.display end,
  }, function(tpl)
    if not tpl then return end
    local function run(name)
      local dest_abs, o_flag, file_path
      if tpl.predefined then
        dest_abs  = out_dir
        o_flag    = out_dir
        file_path = out_dir .. "/" .. tpl.predefined
      else
        local sub  = name:match("^(.+)/[^/]+$")
        local base = name:match("([^/]+)$")
        dest_abs   = sub and (out_dir .. "/" .. sub) or out_dir
        vim.fn.mkdir(dest_abs, "p")
        local rel  = dest_abs:sub(#proj_dir + 2)
        o_flag     = rel ~= "" and rel or "."
        file_path  = dest_abs .. "/" .. base .. tpl.ext
        name       = base
      end
      local args = tpl.predefined
        and { "dotnet", "new", tpl.value, "-o", o_flag }
        or  { "dotnet", "new", tpl.value, "-o", o_flag, "-n", name }
      runner.bg(args, {
        cwd   = proj_dir,
        label = "New " .. (tpl.label or name),
        notify_success = false,
        on_exit = function(code)
          if code ~= 0 then return end
          if tpl.ext == ".cs" and vim.fn.filereadable(file_path) == 1 then
            local ns = namespace_m.compute(proj_node.path, file_path)
            namespace_m.patch_file(file_path, ns)
          end
          refresh()
          if vim.fn.filereadable(file_path) == 1 then
            action_open_file({ path = file_path, kind = "file" })
          end
        end,
      })
    end
    if tpl.predefined then run(nil)
    else
      vim.ui.input({ prompt = "Name (e.g. MyClass or Sub/MyClass): " }, function(name)
        if name and name ~= "" then run(name) end
      end)
    end
  end)
end

local function action_delete(node)
  confirm("Delete '" .. node.path .. "'?", function()
    if node.kind == "dir" then
      vim.fn.delete(node.path, "rf")
    else
      vim.fn.delete(node.path)
    end
    require("dotnet.notify").info("Deleted " .. vim.fn.fnamemodify(node.path, ":t"))
    refresh()
  end)
end

local function action_rename(node)
  local old_name = vim.fn.fnamemodify(node.path, ":t")
  vim.ui.input({ prompt = "Rename to: ", default = old_name }, function(new_name)
    if not new_name or new_name == "" or new_name == old_name then return end
    local new_path = vim.fn.fnamemodify(node.path, ":h") .. "/" .. new_name
    vim.fn.rename(node.path, new_path)
    refresh()
  end)
end

local function action_remove_package(node)
  local proj_dir = vim.fn.fnamemodify(node._proj_path, ":h")
  confirm("Remove package '" .. node._pkg_name .. "'?", function()
    runner.bg({ "dotnet", "remove", "package", node._pkg_name }, {
      cwd   = proj_dir,
      label = "Remove " .. node._pkg_name,
      on_exit = function(code) if code == 0 then refresh() end end,
    })
  end)
end

local function action_remove_projref(node)
  local proj_dir = vim.fn.fnamemodify(node._proj_path, ":h")
  local ref_name = vim.fn.fnamemodify(node._ref_path, ":t:r")
  confirm("Remove reference '" .. ref_name .. "'?", function()
    runner.bg({ "dotnet", "remove", "reference", node._ref_path }, {
      cwd   = proj_dir,
      label = "Remove ref " .. ref_name,
      on_exit = function(code) if code == 0 then refresh() end end,
    })
  end)
end

local function action_remove_from_project(proj_node)
  local proj_dir  = vim.fn.fnamemodify(proj_node.path, ":h")
  local deps_data = project.deps(proj_node.path)
  local items     = {}
  for _, pk in ipairs(deps_data.pkgs) do
    table.insert(items, { label = "pkg: " .. pk.name, kind = "pkg", name = pk.name, proj_dir = proj_dir })
  end
  for _, pr in ipairs(deps_data.refs) do
    table.insert(items, { label = "ref: " .. pr.name, kind = "ref", path = pr.path, proj_dir = proj_dir })
  end
  if #items == 0 then
    require("dotnet.notify").info("No packages or references to remove")
    return
  end
  vim.ui.select(items, {
    prompt      = "Remove from " .. vim.fn.fnamemodify(proj_node.path, ":t:r") .. ":",
    format_item = function(i) return i.label end,
  }, function(item)
    if not item then return end
    local args  = item.kind == "pkg"
      and { "dotnet", "remove", "package", item.name }
      or  { "dotnet", "remove", "reference", item.path }
    local label = item.kind == "pkg" and item.name or vim.fn.fnamemodify(item.path, ":t:r")
    confirm("Remove '" .. label .. "'?", function()
      runner.bg(args, {
        cwd   = item.proj_dir,
        label = "Remove " .. label,
        on_exit = function(code) if code == 0 then refresh() end end,
      })
    end)
  end)
end

local function action_reveal_path(target_path)
  if not S.sln_path then return end
  if not S.win or not vim.api.nvim_win_is_valid(S.win) then M.open() end
  local proj_list = solution.projects(S.sln_path)
  local proj_dir  = nil
  for _, pp in ipairs(proj_list) do
    local pd = vim.fn.fnamemodify(pp, ":h")
    if target_path:sub(1, #pd + 1) == pd .. "/" then
      S.collapsed[pp] = false
      proj_dir = pd
      break
    end
  end
  if not proj_dir then return end
  local dir = vim.fn.fnamemodify(target_path, ":h")
  while #dir > #proj_dir do
    S.collapsed[dir] = false
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then break end
    dir = parent
  end
  refresh()
  for i, n in ipairs(S.nodes) do
    if n.path == target_path then
      pcall(vim.api.nvim_win_set_cursor, S.win, { i + HEADER_OFFSET, 0 })
      return
    end
  end
end

-- ── Fuzzy find ────────────────────────────────────────────────────────────────

local function action_fuzzy_find()
  require("dotnet.telescope.files").open(S.sln_path, function(path)
    action_reveal_path(path)
  end)
end

-- ── Key dispatch ──────────────────────────────────────────────────────────────

local DISPATCH = {
  ["<cr>"] = function(node)
    local leaf = node.kind == "file" or node.kind == "pkg" or node.kind == "projref"
    if leaf then
      if node.kind == "file" then action_open_file(node) end
    else
      action_toggle_fold(node)
    end
  end,

  ["<space>"] = function(node)
    local leaf = node.kind == "file" or node.kind == "pkg" or node.kind == "projref"
    if not leaf then action_toggle_fold(node) end
  end,

  ["n"] = function(node, row)
    if node.kind == "solution" then
      require("dotnet.commands.init").run("solution.new_project")
    elseif node.kind == "project" then
      action_new_item(node)
    else
      local proj = nearest_project(row)
      if proj then
        local target = node.kind == "dir" and node.path
                    or vim.fn.fnamemodify(node.path, ":h")
        action_new_item(proj, target)
      end
    end
  end,

  ["a"] = function(node)
    if node.kind == "solution" then
      require("dotnet.commands.init").run("solution.add_project")
    end
  end,

  ["D"] = function(node)
    if     node.kind == "solution" then require("dotnet.commands.init").run("solution.remove_project")
    elseif node.kind == "project"  then action_remove_from_project(node)
    elseif node.kind == "pkg"      then action_remove_package(node)
    elseif node.kind == "projref"  then action_remove_projref(node)
    elseif node.kind == "file" or node.kind == "dir" then action_delete(node)
    end
  end,

  ["r"] = function(node)
    if node.kind == "file" or node.kind == "dir" then action_rename(node) end
  end,

  ["b"] = function(node, row)
    local proj = node.kind == "project" and node or nearest_project(row)
    if proj then runner.build(proj.path) end
  end,

  ["B"] = function()
    if S.sln_path then runner.build(S.sln_path) end
  end,

  ["t"] = function(node, row)
    local proj = node.kind == "project" and node or nearest_project(row)
    if proj then runner.test(proj.path) end
  end,

  ["T"] = function()
    if S.sln_path then runner.test(S.sln_path) end
  end,

  ["R"] = function(node, row)
    local proj = node.kind == "project" and node or nearest_project(row)
    if proj and project.runnable(proj.path) then
      runner.run(proj.path)
    end
  end,

  ["W"] = function(node)
    S.collapsed[node.path] = true
    local row = vim.api.nvim_win_get_cursor(S.win)[1]
    refresh()
    pcall(vim.api.nvim_win_set_cursor, S.win, { row, 0 })
  end,

  ["E"] = function(node)
    S.collapsed[node.path] = false
    local row = vim.api.nvim_win_get_cursor(S.win)[1]
    refresh()
    pcall(vim.api.nvim_win_set_cursor, S.win, { row, 0 })
  end,

  ["H"] = function()
    S.show_hidden = not S.show_hidden
    refresh()
  end,

  ["x"] = function()
    runner.stop_all()
  end,

  ["/"] = function()
    action_fuzzy_find()
  end,

  ["?"] = function()
    require("dotnet.ui.explorer_help").toggle()
  end,
}

-- ── Window setup ──────────────────────────────────────────────────────────────

local function setup_keymaps()
  local o = { noremap = true, silent = true, buffer = S.buf }
  for key, fn in pairs(DISPATCH) do
    vim.keymap.set("n", key, function()
      local node, row = current_node()
      if node then fn(node, row) end
    end, o)
  end
  vim.keymap.set("n", "<F5>",  refresh,  o)
  vim.keymap.set("n", "q",     M.close,  o)
  vim.keymap.set("n", "<esc>", M.close,  o)
  vim.keymap.set("n", "gx",    function() require("dotnet.telescope.jobs").open() end, o)
  vim.keymap.set("n", "<Tab>", function()
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if w ~= S.win then
        local bt = vim.bo[vim.api.nvim_win_get_buf(w)].buftype
        if bt == "" or bt == "acwrite" then
          vim.api.nvim_set_current_win(w)
          return
        end
      end
    end
  end, o)
end

local function open_win()
  S.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[S.buf].filetype   = "dotnet_explorer"
  vim.bo[S.buf].bufhidden  = "wipe"
  vim.bo[S.buf].modifiable = false
  vim.bo[S.buf].buftype    = "nofile"
  vim.bo[S.buf].buflisted  = false
  vim.api.nvim_buf_set_name(S.buf, "Solution Explorer")

  local width = panel_width()
  vim.cmd("topleft " .. width .. "vsplit")
  S.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(S.win, S.buf)

  local wo = vim.wo[S.win]
  wo.number         = false
  wo.relativenumber = false
  wo.signcolumn     = "no"
  wo.foldcolumn     = "0"
  wo.wrap           = false
  wo.winfixwidth    = true
  wo.cursorline     = true
  wo.winbar         = ""
  wo.statuscolumn   = ""
  wo.winhighlight   = "Normal:NvimTreeNormal,NormalNC:NvimTreeNormalNC,CursorLine:NvimTreeCursorLine,WinSeparator:WinSeparator"
  vim.opt_local.fillchars = { eob = " ", vert = "▕", vertright = "▕", vertleft = "▕" }
end

-- ── Public API ────────────────────────────────────────────────────────────────

local _saved_showtabline = nil

function M.set_sln(sln_path)
  S.sln_path = sln_path
  if S.win and vim.api.nvim_win_is_valid(S.win) then refresh() end
end

function M.open()
  if S.win and vim.api.nvim_win_is_valid(S.win) then return end
  if not S.sln_path then
    S.sln_path = solution.find()
    if not S.sln_path then
      require("dotnet.notify").warn("No .sln/.slnx found in cwd")
      return
    end
  end
  -- hide tabline so panel fills flush to the top edge
  _saved_showtabline = vim.o.showtabline
  vim.o.showtabline = 0
  open_win()
  setup_keymaps()
  refresh()
end

function M.close()
  if S.win and vim.api.nvim_win_is_valid(S.win) then
    vim.api.nvim_win_close(S.win, true)
  end
  S.win = nil
  S.buf = nil
  -- restore tabline
  if _saved_showtabline ~= nil then
    vim.o.showtabline = _saved_showtabline
    _saved_showtabline = nil
  end
end

function M.toggle()
  if S.win and vim.api.nvim_win_is_valid(S.win) then M.close()
  else
    require("dotnet.commands.init").close_dashboard()
    M.open()
  end
end

function M.reveal()
  if not S.win or not vim.api.nvim_win_is_valid(S.win) then M.open() end
  local cur = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  if cur == "" then return end
  -- Try visible nodes first
  for i, n in ipairs(S.nodes) do
    if n.path == cur then
      pcall(vim.api.nvim_win_set_cursor, S.win, { i, 0 })
      return
    end
  end
  -- Expand parents and try again
  action_reveal_path(cur)
end

return M
