-- dotnet.nvim — VS-style Test Explorer panel
-- Shows a tree: Solution → Project → Namespace → Class → Method
-- Runs tests, displays pass/fail/skip icons inline.

local runner   = require("dotnet.core.runner")
local solution = require("dotnet.core.solution")
local M        = {}

-- ── State ────────────────────────────────────────────────────────────────────

local S = {
  buf      = nil,
  win      = nil,
  sln_path = nil,
  nodes    = {},       -- flat list, each node has depth, kind, label, state, fqn, proj
  ns       = vim.api.nvim_create_namespace("dotnet_test_explorer"),
}

-- ── Icons / highlights ────────────────────────────────────────────────────────

local ICON = {
  solution  = "󰘦 ",
  project   = " ",
  namespace = "󰅪 ",
  class     = " ",
  method    = " ",
  -- state icons
  none      = "  ",
  running   = "󰔟 ",
  passed    = " ",
  failed    = " ",
  skipped   = "󰅙 ",
}

local HL = {
  passed    = "DiagnosticOk",
  failed    = "DiagnosticError",
  skipped   = "DiagnosticWarn",
  running   = "DiagnosticInfo",
  namespace = "Directory",
  class     = "Type",
  method    = "Function",
  solution  = "Title",
  project   = "Statement",
}

-- ── Test discovery ────────────────────────────────────────────────────────────

-- Parse `dotnet test --list-tests` output into a tree structure per project.
-- Output format (one FQN per line after the header):
--   Namespace.ClassName.MethodName
local function discover_project(proj_path, cb)
  local proj_dir = vim.fn.fnamemodify(proj_path, ":h")
  local lines = {}
  vim.fn.jobstart({
    "dotnet", "test", "--list-tests", "--nologo", "-v", "q"
  }, {
    cwd             = proj_dir,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      for _, l in ipairs(data) do
        local t = vim.trim(l)
        if t ~= "" then table.insert(lines, t) end
      end
    end,
    on_exit = function()
      -- Skip header lines (they contain spaces/dashes, not FQNs)
      local tests = {}
      for _, l in ipairs(lines) do
        if not l:match("^%-") and not l:match("^%s*$") and l:match("%.") then
          table.insert(tests, l)
        end
      end
      cb(tests)
    end,
  })
end

-- Build a node tree from discovered FQNs for one project.
-- Returns flat list of nodes with { depth, kind, label, fqn, proj, state, collapsed }
local function fqns_to_nodes(proj_path, fqns)
  -- Build nested table: ns_map[ns][class] = {methods}
  local ns_map   = {}
  local ns_order = {}
  for _, fqn in ipairs(fqns) do
    local parts = vim.split(fqn, "%.")
    local method = table.remove(parts)
    local class  = table.remove(parts)
    local ns     = table.concat(parts, ".")
    if not ns_map[ns] then
      ns_map[ns]   = {}
      table.insert(ns_order, ns)
    end
    if not ns_map[ns][class] then
      ns_map[ns][class] = {}
    end
    table.insert(ns_map[ns][class], { label = method, fqn = fqn })
  end

  local nodes = {}
  local proj_name = vim.fn.fnamemodify(proj_path, ":t:r")
  table.insert(nodes, {
    depth     = 1,
    kind      = "project",
    label     = proj_name,
    proj      = proj_path,
    fqn       = nil,
    state     = "none",
    collapsed = false,
  })

  for _, ns in ipairs(ns_order) do
    table.insert(nodes, {
      depth     = 2,
      kind      = "namespace",
      label     = ns ~= "" and ns or "(global)",
      proj      = proj_path,
      fqn       = nil,
      state     = "none",
      collapsed = false,
    })
    -- sort classes
    local classes = {}
    for cls in pairs(ns_map[ns]) do table.insert(classes, cls) end
    table.sort(classes)
    for _, cls in ipairs(classes) do
      table.insert(nodes, {
        depth     = 3,
        kind      = "class",
        label     = cls,
        proj      = proj_path,
        fqn       = (ns ~= "" and (ns .. ".") or "") .. cls,
        state     = "none",
        collapsed = false,
      })
      table.sort(ns_map[ns][cls], function(a, b) return a.label < b.label end)
      for _, m in ipairs(ns_map[ns][cls]) do
        table.insert(nodes, {
          depth     = 4,
          kind      = "method",
          label     = m.label,
          proj      = proj_path,
          fqn       = m.fqn,
          state     = "none",
          collapsed = false,
        })
      end
    end
  end
  return nodes
end

-- ── Render ────────────────────────────────────────────────────────────────────

local function render()
  if not S.buf or not vim.api.nvim_buf_is_valid(S.buf) then return end
  vim.bo[S.buf].modifiable = true
  vim.api.nvim_buf_clear_namespace(S.buf, S.ns, 0, -1)

  local lines = {}
  local hls   = {}   -- { lnum, hl_group, col_s, col_e }

  -- Header
  local header = "  Test Explorer"
  table.insert(lines, header)
  table.insert(hls, { 0, "Title", 0, -1 })
  table.insert(lines, string.rep("─", 30))

  -- Walk nodes; skip children of collapsed parent
  local skip_until_depth = nil
  for _, node in ipairs(S.nodes) do
    if skip_until_depth and node.depth > skip_until_depth then
      goto continue
    else
      skip_until_depth = nil
    end

    local indent = string.rep("  ", node.depth - 1)
    local icon   = ICON[node.kind] or "  "
    local state  = ICON[node.state] or ICON.none
    local toggle = ""
    if node.kind ~= "method" then
      toggle = node.collapsed and "▶ " or "▼ "
    else
      toggle = "  "
    end
    local line = indent .. toggle .. state .. icon .. node.label
    local lnum = #lines
    table.insert(lines, line)

    -- highlights
    local state_hl = node.state ~= "none" and HL[node.state] or nil
    if state_hl then
      local state_col = #indent + #toggle
      table.insert(hls, { lnum, state_hl, state_col, state_col + #state })
    end
    local label_col = #indent + #toggle + #state + #icon
    local kind_hl   = HL[node.kind]
    if kind_hl then
      table.insert(hls, { lnum, kind_hl, label_col, -1 })
    end

    if node.collapsed and node.kind ~= "method" then
      skip_until_depth = node.depth
    end

    ::continue::
  end

  vim.api.nvim_buf_set_lines(S.buf, 0, -1, false, lines)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(S.buf, S.ns, h[2], h[1], h[3], h[4])
  end
  vim.bo[S.buf].modifiable = false
end

-- ── Cursor helpers ────────────────────────────────────────────────────────────

local HEADER_OFFSET = 2  -- header line + separator

local function cursor_node()
  if not S.win or not vim.api.nvim_win_is_valid(S.win) then return nil, nil end
  local row = vim.api.nvim_win_get_cursor(S.win)[1]
  local idx  = row - HEADER_OFFSET
  -- account for collapsed parents
  local visible = 0
  local skip_depth = nil
  for i, node in ipairs(S.nodes) do
    if skip_depth and node.depth > skip_depth then
      goto cont
    else
      skip_depth = nil
    end
    visible = visible + 1
    if visible == idx then return node, i end
    if node.collapsed and node.kind ~= "method" then
      skip_depth = node.depth
    end
    ::cont::
  end
  return nil, nil
end

-- ── Run helpers ───────────────────────────────────────────────────────────────

local function set_state(fqn_or_proj, state, is_proj)
  for _, node in ipairs(S.nodes) do
    if is_proj then
      if node.proj == fqn_or_proj then node.state = state end
    else
      if node.fqn == fqn_or_proj then node.state = state end
    end
  end
  vim.schedule(render)
end

-- Parse `dotnet test` verbose output for pass/fail/skip lines.
-- Format: "  Passed  FQN [time]" or "  Failed  FQN [time]"
local function parse_results(lines)
  local results = {}
  for _, l in ipairs(lines) do
    local state, fqn = l:match("^%s+(%a+)%s+(.-)%s+%[")
    if state and fqn then
      state = state:lower()
      if state == "passed" or state == "failed" or state == "skipped" then
        results[fqn] = state
      end
    end
  end
  return results
end

local function run_tests(filter, proj_path, label)
  -- Mark running
  for _, node in ipairs(S.nodes) do
    if node.proj == proj_path then
      if filter == nil or (node.fqn and node.fqn:find(filter, 1, true)) then
        node.state = "running"
      end
    end
  end
  render()

  local args = { "dotnet", "test", "--nologo", "-v", "normal" }
  if filter then
    vim.list_extend(args, { "--filter", filter })
  end

  local out = {}
  vim.fn.jobstart(args, {
    cwd             = vim.fn.fnamemodify(proj_path, ":h"),
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      for _, l in ipairs(data) do
        if l ~= "" then table.insert(out, l) end
      end
    end,
    on_stderr = function(_, data)
      for _, l in ipairs(data) do
        if l ~= "" then table.insert(out, l) end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        local results = parse_results(out)
        for fqn, st in pairs(results) do
          for _, node in ipairs(S.nodes) do
            if node.fqn == fqn then node.state = st end
          end
        end
        -- roll up to class/ns/project
        local function roll_up(depth_child, depth_parent, key_fn)
          local parent_state = {}
          for _, node in ipairs(S.nodes) do
            if node.depth == depth_child and node.state ~= "none" and node.state ~= "running" then
              local pk = key_fn(node)
              local cur = parent_state[pk]
              if cur == nil then
                parent_state[pk] = node.state
              elseif cur == "passed" and node.state ~= "passed" then
                parent_state[pk] = node.state
              elseif cur == "skipped" and node.state == "failed" then
                parent_state[pk] = "failed"
              end
            end
          end
          for _, node in ipairs(S.nodes) do
            if node.depth == depth_parent then
              local pk = key_fn(node) -- same key logic for parent
              if parent_state[pk] then node.state = parent_state[pk] end
            end
          end
        end
        -- method→class: key = proj+class_fqn, ns→proj: key = proj
        -- simple approach: match by label prefix
        for _, node in ipairs(S.nodes) do
          if node.depth == 4 and node.fqn and not results[node.fqn] then
            if node.state == "running" then node.state = "none" end
          end
        end
        -- Roll up classes from methods
        for _, cls_node in ipairs(S.nodes) do
          if cls_node.depth == 3 then
            local worst = nil
            for _, m in ipairs(S.nodes) do
              if m.depth == 4 and m.proj == cls_node.proj
                  and m.fqn and m.fqn:sub(1, #cls_node.fqn) == cls_node.fqn then
                if m.state ~= "none" and m.state ~= "running" then
                  if worst == nil then worst = m.state
                  elseif worst == "passed" then worst = m.state
                  elseif worst == "skipped" and m.state == "failed" then worst = "failed"
                  end
                end
              end
            end
            if worst then cls_node.state = worst end
          end
        end
        -- Roll up ns from classes, project from ns
        for _, p in ipairs(S.nodes) do
          if p.depth == 1 then
            local worst = nil
            for _, n in ipairs(S.nodes) do
              if n.proj == p.proj and n.depth == 3 and n.state ~= "none" and n.state ~= "running" then
                if worst == nil then worst = n.state
                elseif worst == "passed" then worst = n.state
                elseif worst == "skipped" and n.state == "failed" then worst = "failed"
                end
              end
            end
            if worst then p.state = worst end
          end
        end
        if code ~= 0 and vim.tbl_isempty(results) then
          vim.notify("[dotnet] " .. label .. " failed (exit " .. code .. ")", vim.log.levels.ERROR)
        end
        render()
      end)
    end,
  })
end

-- ── Refresh (re-discover) ─────────────────────────────────────────────────────

local function refresh()
  if not S.sln_path then return end
  local projs = solution.projects(S.sln_path)
  if not projs or #projs == 0 then
    S.nodes = {}
    render()
    return
  end

  -- Insert solution root
  S.nodes = {{
    depth     = 0,
    kind      = "solution",
    label     = vim.fn.fnamemodify(S.sln_path, ":t:r"),
    proj      = nil,
    fqn       = nil,
    state     = "none",
    collapsed = false,
  }}

  local pending = #projs
  local all_nodes = {}

  for _, proj in ipairs(projs) do
    discover_project(proj, function(fqns)
      local nodes = fqns_to_nodes(proj, fqns)
      for _, n in ipairs(nodes) do
        n.depth = n.depth + 1  -- shift down one level (under solution)
        table.insert(all_nodes, n)
      end
      pending = pending - 1
      if pending == 0 then
        vim.schedule(function()
          for _, n in ipairs(all_nodes) do
            table.insert(S.nodes, n)
          end
          render()
        end)
      end
    end)
  end
end

-- ── Keymap dispatch ───────────────────────────────────────────────────────────

local function setup_keymaps()
  local map = function(lhs, fn)
    vim.api.nvim_buf_set_keymap(S.buf, "n", lhs, "", {
      noremap = true, silent = true, callback = fn
    })
  end

  -- Toggle collapse
  map("<Space>", function()
    local node = cursor_node()
    if not node or node.kind == "method" then return end
    node.collapsed = not node.collapsed
    render()
  end)

  map("<CR>", function()
    local node = cursor_node()
    if not node then return end
    if node.kind == "method" then
      -- Run single test
      run_tests(node.fqn, node.proj, node.label)
    elseif node.kind == "class" then
      run_tests(node.fqn, node.proj, node.label)
    else
      node.collapsed = not node.collapsed
      render()
    end
  end)

  -- Run under cursor
  map("r", function()
    local node = cursor_node()
    if not node then return end
    if node.kind == "method" then
      run_tests(node.fqn, node.proj, node.label)
    elseif node.kind == "class" then
      run_tests(node.fqn, node.proj, node.label)
    elseif node.kind == "project" then
      run_tests(nil, node.proj, "project")
    elseif node.kind == "solution" then
      for _, proj in ipairs(solution.projects(S.sln_path)) do
        run_tests(nil, proj, "solution")
      end
    end
  end)

  -- Run all
  map("R", function()
    if not S.sln_path then return end
    for _, node in ipairs(S.nodes) do node.state = "none" end
    for _, proj in ipairs(solution.projects(S.sln_path)) do
      run_tests(nil, proj, "all")
    end
  end)

  -- Run failed
  map("f", function()
    for _, node in ipairs(S.nodes) do
      if node.kind == "method" and node.state == "failed" then
        run_tests(node.fqn, node.proj, node.label)
      end
    end
  end)

  -- Refresh discovery
  map("e", function() refresh() end)
  map("<F5>", function()
    for _, node in ipairs(S.nodes) do node.state = "none" end
    if S.sln_path then
      for _, proj in ipairs(solution.projects(S.sln_path)) do
        run_tests(nil, proj, "all")
      end
    end
  end)

  -- Clear results
  map("c", function()
    for _, node in ipairs(S.nodes) do node.state = "none" end
    render()
  end)

  -- Collapse/expand all
  map("zM", function()
    for _, node in ipairs(S.nodes) do
      if node.kind ~= "method" then node.collapsed = true end
    end
    render()
  end)
  map("zR", function()
    for _, node in ipairs(S.nodes) do node.collapsed = false end
    render()
  end)

  -- Close
  map("q", function() M.close() end)

  -- Help hint
  map("?", function()
    local lines = {
      " Test Explorer Keys ",
      "",
      "  <CR>    Run test/class or toggle",
      "  <Space> Toggle collapse",
      "  r       Run node under cursor",
      "  R       Run all tests",
      "  f       Re-run failed tests",
      "  c       Clear results",
      "  e       Refresh (re-discover tests)",
      "  <F5>    Run all tests",
      "  zM      Collapse all",
      "  zR      Expand all",
      "  q       Close",
      "  ?       This help",
    }
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end)
end

-- ── Window management ─────────────────────────────────────────────────────────

local function open_win()
  local width = 40
  vim.cmd("topleft " .. width .. "vsplit")
  S.win = vim.api.nvim_get_current_win()
  S.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(S.win, S.buf)

  local bo = vim.bo[S.buf]
  bo.buftype   = "nofile"
  bo.bufhidden = "hide"
  bo.swapfile  = false
  bo.filetype  = "dotnet_test_explorer"

  local wo = vim.wo[S.win]
  wo.number         = false
  wo.relativenumber = false
  wo.signcolumn     = "no"
  wo.wrap           = false
  wo.cursorline     = true
  wo.winfixwidth    = true

  vim.api.nvim_buf_set_name(S.buf, "Test Explorer")
  setup_keymaps()
  vim.api.nvim_create_autocmd("WinClosed", {
    buffer = S.buf,
    once   = true,
    callback = function()
      S.win = nil
      S.buf = nil
    end,
  })
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.set_sln(path)
  S.sln_path = path
end

function M.open()
  if S.win and vim.api.nvim_win_is_valid(S.win) then
    vim.api.nvim_set_current_win(S.win)
    return
  end
  open_win()
  render()
  refresh()
end

function M.close()
  if S.win and vim.api.nvim_win_is_valid(S.win) then
    vim.api.nvim_win_close(S.win, true)
  end
  S.win = nil
  S.buf = nil
end

function M.toggle()
  if S.win and vim.api.nvim_win_is_valid(S.win) then
    M.close()
  else
    M.open()
  end
end

return M
