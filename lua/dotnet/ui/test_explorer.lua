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
  -- state icons (plain Unicode — always renders)
  none      = "  ",
  running   = "󰔟 ",
  passed    = "✓ ",
  failed    = "✗ ",
  skipped   = "○ ",
}

local STATE_SUFFIX = {
  passed  = "  Success",
  failed  = "  Failed",
  skipped = "  Skipped",
}

-- Define reliable highlight groups (link to standard groups)
vim.api.nvim_set_hl(0, "DotnetTestPassed",  { link = "DiagnosticOk",   default = true })
vim.api.nvim_set_hl(0, "DotnetTestFailed",  { link = "DiagnosticError", default = true })
vim.api.nvim_set_hl(0, "DotnetTestSkipped", { link = "DiagnosticWarn",  default = true })
vim.api.nvim_set_hl(0, "DotnetTestRunning", { link = "DiagnosticInfo",  default = true })
vim.api.nvim_set_hl(0, "DotnetTestTotal",   { link = "DiagnosticWarn",  default = true })

local HL = {
  passed    = "DotnetTestPassed",
  failed    = "DotnetTestFailed",
  skipped   = "DotnetTestSkipped",
  running   = "DotnetTestRunning",
  namespace = "Directory",
  class     = "Type",
  method    = "Function",
  solution  = "Title",
  project   = "Statement",
}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function short(name)
  local parts = vim.split(name, ".", { plain = true })
  if #parts <= 2 then return name end
  return parts[#parts - 1] .. "." .. parts[#parts]
end

-- ── Test discovery ────────────────────────────────────────────────────────────

local _cache = {}   -- proj_path → { fqns }

-- Parse `dotnet test --list-tests` output into a tree structure per project.
-- Output format (one FQN per line after the header):
--   Namespace.ClassName.MethodName
local function discover_project(proj_path, cb)
  if _cache[proj_path] then return cb(_cache[proj_path]) end
  local proj_dir = vim.fn.fnamemodify(proj_path, ":h")
  local lines = {}
  vim.fn.jobstart({
    "dotnet", "test", "--list-tests", "--no-build", "--nologo", "-v", "q"
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
      -- Collect test FQNs that appear after the "The following Tests are available:" header.
      -- Parameterized tests may contain '(', ')', ',', '"', '<', '>' in their names.
      local tests = {}
      local after_header = false
      for _, l in ipairs(lines) do
        local t = vim.trim(l)
        if t:find("The following Tests are available", 1, true) then
          after_header = true
        elseif after_header and t ~= "" then
          -- Must start with a letter/underscore and contain at least one dot segment
          if t:match("^[%a_][%w_%.%(%),<>\"' %-]*%.[%w_][%w_%(%),<>\"' %-]*$") then
            table.insert(tests, t)
          end
        end
      end
      -- Fallback: if header was never found use the old heuristic (plain FQNs only)
      if not after_header then
        for _, l in ipairs(lines) do
          local t = vim.trim(l)
          if t:match("^[%a_][%w_]*%.[%w_%.]+$") then
            table.insert(tests, t)
          end
        end
      end
      _cache[proj_path] = tests
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
  local proj_name = short(vim.fn.fnamemodify(proj_path, ":t:r"))
  table.insert(nodes, {
    depth     = 1,
    kind      = "project",
    label     = proj_name,
    proj      = proj_path,
    fqn       = nil,
    state     = "none",
    collapsed = true,
  })

  for _, ns in ipairs(ns_order) do
    table.insert(nodes, {
      depth     = 2,
      kind      = "namespace",
      label     = ns ~= "" and short(ns) or "(global)",
      proj      = proj_path,
      fqn       = nil,
      state     = "none",
      collapsed = true,
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

  -- Count methods
  local passed, failed, total = 0, 0, 0
  for _, node in ipairs(S.nodes) do
    if node.kind == "method" then
      total  = total  + 1
      if node.state == "passed" then passed = passed + 1
      elseif node.state == "failed" then failed = failed + 1
      end
    end
  end

  -- Header with inline stats: "  Test Explorer   0  0  340"
  local p_str, f_str, t_str = tostring(passed), tostring(failed), tostring(total)
  local prefix = "  Test Explorer   "
  local header = prefix .. p_str .. "  " .. f_str .. "  " .. t_str
  table.insert(lines, header)
  table.insert(hls, { 0, "Title", 0, #prefix })
  local p_col = #prefix
  local f_col = p_col + #p_str + 2
  local t_col = f_col + #f_str + 2
  table.insert(hls, { 0, "DotnetTestPassed", p_col, p_col + #p_str })
  table.insert(hls, { 0, "DotnetTestFailed", f_col, f_col + #f_str })
  table.insert(hls, { 0, "DotnetTestTotal",  t_col, t_col + #t_str })

  local width = S.win and vim.api.nvim_win_is_valid(S.win) and vim.api.nvim_win_get_width(S.win) or 40
  table.insert(lines, string.rep("─", width))

  -- Walk nodes; skip children of collapsed parent
  local skip_until_depth = nil
  for _, node in ipairs(S.nodes) do
    if skip_until_depth and node.depth > skip_until_depth then
      goto continue
    else
      skip_until_depth = nil
    end

    local indent     = string.rep("  ", node.depth - 1)
    local kind_icon  = ICON[node.kind] or "  "
    local state_icon = ICON[node.state] or ICON.none
    local toggle = node.kind ~= "method"
      and (node.collapsed and "▶ " or "▼ ")
      or  "  "
    local suffix = STATE_SUFFIX[node.state] or ""

    local line = indent .. toggle .. state_icon .. kind_icon .. node.label .. suffix
    local lnum = #lines
    table.insert(lines, line)

    -- Column positions (all byte-based)
    local state_col = #indent + #toggle
    local label_col = state_col + #state_icon + #kind_icon
    local suffix_col = label_col + #node.label

    local state_hl = (node.state ~= "none") and HL[node.state] or nil

    -- State icon highlight
    if state_hl then
      table.insert(hls, { lnum, state_hl, state_col, state_col + #state_icon })
    end
    -- Label: use state colour when passed/failed/skipped, otherwise kind colour
    if state_hl and node.state ~= "running" then
      table.insert(hls, { lnum, state_hl, label_col, suffix_col })
    else
      local kind_hl = HL[node.kind]
      if kind_hl then
        table.insert(hls, { lnum, kind_hl, label_col, suffix_col })
      end
    end
    -- Suffix (e.g. "  Success") in same state colour, dimmer
    if suffix ~= "" and state_hl then
      table.insert(hls, { lnum, "Comment", suffix_col, -1 })
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

local HEADER_OFFSET = 2  -- header + separator

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

-- Parse a TRX results directory.
-- TRX stores testName as the short method name; className lives in TestDefinitions.
-- We build full FQNs by combining className + "." + methodName.
-- Returns { ["Full.FQN"] = "passed"|"failed"|"skipped" }
local function parse_trx_dir(dir)
  local trx_files = vim.fn.glob(dir .. "/*.trx", false, true)
  if not trx_files or #trx_files == 0 then
    vim.fn.delete(dir, "rf")
    return {}
  end

  local ok, lines = pcall(vim.fn.readfile, trx_files[1])
  vim.fn.delete(dir, "rf")   -- delete AFTER reading
  if not ok then return {} end

  -- Pass 1: testId → full FQN from <TestDefinitions>
  -- <UnitTest name="Method" id="uuid"> ... <TestMethod className="NS.Class" name="Method" /> ... </UnitTest>
  local id_to_fqn = {}
  local current_id = nil
  for _, l in ipairs(lines) do
    local id = l:match('<UnitTest[^>]+%sid="([^"]+)"')
    if id then current_id = id end
    if current_id then
      local cls  = l:match('className="([^"]+)"')
      local meth = l:match('<TestMethod[^>]+%sname="([^"]+)"')
      if cls and meth then
        id_to_fqn[current_id] = cls .. "." .. meth
        current_id = nil
      end
    end
  end

  -- Pass 2: testId → outcome from <Results>
  local results = {}
  for _, l in ipairs(lines) do
    if l:find("UnitTestResult") and l:find('testId=') and l:find('outcome=') then
      local tid     = l:match('testId="([^"]+)"')
      local outcome = l:match('outcome="([^"]+)"')
      if tid and outcome then
        local fqn = id_to_fqn[tid]
        if fqn then
          local st = outcome:lower()
          if     st == "passed"      then results[fqn] = "passed"
          elseif st == "failed"      then results[fqn] = "failed"
          elseif st == "notexecuted" or st == "skipped" then results[fqn] = "skipped"
          end
        end
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
  require("dotnet.ui.test_signs").mark_running(proj_path)
  render()
  vim.cmd("redraw")

  local results_dir = vim.fn.tempname()
  vim.fn.mkdir(results_dir, "p")
  local args = { "dotnet", "test", "--nologo",
                 "--logger", "trx",
                 "--results-directory", results_dir }
  if filter then
    vim.list_extend(args, { "--filter", filter })
  end

  vim.fn.jobstart(args, {
    cwd     = vim.fn.fnamemodify(proj_path, ":h"),
    on_exit = function(_, code)
      vim.schedule(function()
        local results = parse_trx_dir(results_dir)
        -- FQN matching: dotnet output may emit short FQNs (ClassName.Method)
        -- while stored FQNs are fully qualified (Namespace.ClassName.Method).
        -- Match by suffix so both short and full forms resolve correctly.
        local function fqn_matches(node_fqn, result_fqn)
          if node_fqn == result_fqn then return true end
          -- node_fqn ends with result_fqn (suffix match with dot boundary)
          if #node_fqn >= #result_fqn then
            local suffix = node_fqn:sub(-(#result_fqn))
            if suffix == result_fqn then
              local boundary = node_fqn:sub(-(#result_fqn) - 1, -(#result_fqn) - 1)
              return boundary == "." or boundary == ""
            end
          end
          return false
        end

        for fqn, st in pairs(results) do
          for _, node in ipairs(S.nodes) do
            if node.fqn and fqn_matches(node.fqn, fqn) then node.state = st end
          end
        end

        -- After shift in refresh(), depths are: project=2, namespace=3, class=4, method=5
        -- Clear "running" on methods that had no result
        for _, node in ipairs(S.nodes) do
          if node.depth == 5 and node.fqn and node.state == "running" then
            -- check if any result matched
            local matched = false
            for fqn, _ in pairs(results) do
              if fqn_matches(node.fqn, fqn) then matched = true; break end
            end
            if not matched then node.state = "none" end
          end
        end

        -- Roll up methods (depth=5) → classes (depth=4)
        for _, cls_node in ipairs(S.nodes) do
          if cls_node.depth == 4 and cls_node.fqn then
            local worst = nil
            for _, m in ipairs(S.nodes) do
              if m.depth == 5 and m.proj == cls_node.proj
                  and m.fqn and m.fqn:sub(1, #cls_node.fqn + 1) == cls_node.fqn .. "." then
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

        -- Roll up classes (depth=4) → namespace (depth=3)
        -- Class FQN = "Namespace.ClassName", namespace label = "Namespace"
        for _, ns_node in ipairs(S.nodes) do
          if ns_node.depth == 3 and ns_node.proj then
            local ns_prefix = ns_node.label ~= "(global)" and (ns_node.label .. ".") or ""
            local worst = nil
            for _, n in ipairs(S.nodes) do
              if n.proj == ns_node.proj and n.depth == 4 and n.fqn
                  and n.state ~= "none" and n.state ~= "running"
                  and (ns_prefix == "" or n.fqn:sub(1, #ns_prefix) == ns_prefix) then
                if worst == nil then worst = n.state
                elseif worst == "passed" then worst = n.state
                elseif worst == "skipped" and n.state == "failed" then worst = "failed"
                end
              end
            end
            ns_node.state = worst or "none"
          end
        end

        -- Roll up classes (depth=4) → project (depth=2)
        for _, p in ipairs(S.nodes) do
          if p.depth == 2 then
            local worst = nil
            for _, n in ipairs(S.nodes) do
              if n.proj == p.proj and n.depth == 4 and n.state ~= "none" and n.state ~= "running" then
                if worst == nil then worst = n.state
                elseif worst == "passed" then worst = n.state
                elseif worst == "skipped" and n.state == "failed" then worst = "failed"
                end
              end
            end
            if worst then p.state = worst end
          end
        end
        -- Annotate open .cs buffers with pass/fail signs + virtual text
        require("dotnet.ui.test_signs").annotate(results)

        -- Always clear any nodes stuck in "running"
        for _, node in ipairs(S.nodes) do
          if node.state == "running" then node.state = "none" end
        end

        -- Summary notification
        local notify = require("dotnet.notify")
        local total, passed, failed = 0, 0, 0
        for _, st in pairs(results) do
          total = total + 1
          if st == "passed" then passed = passed + 1
          elseif st == "failed" then failed = failed + 1
          end
        end
        if total > 0 then
          if failed > 0 then
            notify.fail(label .. ": " .. failed .. " failed, " .. passed .. "/" .. total .. " passed")
          else
            notify.ok(label .. ": all " .. total .. " passed")
          end
        elseif code ~= 0 then
          notify.fail(label .. " — build failed, press gx to see log")
        else
          notify.ok(label .. " — complete")
        end
        render()
      end)
    end,
  })
end

-- ── Refresh (re-discover) ─────────────────────────────────────────────────────

local function refresh(force)
  if force then _cache = {} end
  if not S.sln_path then return end
  local all_projs = solution.projects(S.sln_path)
  -- only show test projects
  local proj_m = require("dotnet.core.project")
  local projs = vim.tbl_filter(function(p)
    return proj_m.kind(p) == "test"
  end, all_projs)
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
    -- only run test projects (same filter as refresh)
    local proj_m = require("dotnet.core.project")
    for _, proj in ipairs(solution.projects(S.sln_path)) do
      if proj_m.kind(proj) == "test" then
        run_tests(nil, proj, "all")
      end
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

  -- Debug test project under cursor
  map("d", function()
    local node = cursor_node()
    if not node or not node.proj then return end
    require("dotnet.dap.init").debug_test_project(node.proj)
  end)

  -- Refresh discovery
  map("e", function() refresh(true) end)
  map("<F5>", function()
    for _, node in ipairs(S.nodes) do node.state = "none" end
    if S.sln_path then
      local proj_m = require("dotnet.core.project")
      for _, proj in ipairs(solution.projects(S.sln_path)) do
        if proj_m.kind(proj) == "test" then
          run_tests(nil, proj, "all")
        end
      end
    end
  end)

  -- Clear results
  map("c", function()
    for _, node in ipairs(S.nodes) do node.state = "none" end
    render()
  end)

  -- Collapse current node / expand current node one level
  map("W", function()
    local node = cursor_node()
    if node and node.kind ~= "method" then
      node.collapsed = true
      render()
    end
  end)
  map("E", function()
    local node = cursor_node()
    if node and node.kind ~= "method" then
      node.collapsed = false
      render()
    end
  end)
  -- Collapse / expand ALL
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

  -- Go to test file (find .cs file containing the class)
  map("gf", function()
    local node = cursor_node()
    if not node or not node.proj then return end
    local class_name
    if node.kind == "method" and node.fqn then
      local parts = vim.split(node.fqn, "%.")
      class_name = parts[#parts - 1]
    elseif node.kind == "class" and node.fqn then
      local parts = vim.split(node.fqn, "%.")
      class_name = parts[#parts]
    end
    if not class_name then return end
    local proj_dir = vim.fn.fnamemodify(node.proj, ":h")
    local files = vim.fn.globpath(proj_dir, "**/" .. class_name .. ".cs", false, true)
    if not files or #files == 0 then
      require("dotnet.notify").warn("No file found for class " .. class_name)
      return
    end
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
      vim.api.nvim_set_current_win(S.win)
    end
    vim.api.nvim_win_call(target, function()
      vim.cmd("edit " .. vim.fn.fnameescape(files[1]))
    end)
    vim.api.nvim_set_current_win(target)
  end)

  -- Tab: jump to editor window (prevents NvChad tabufline crash)
  map("<Tab>", function()
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if w ~= S.win then
        local bt = vim.bo[vim.api.nvim_win_get_buf(w)].buftype
        if bt == "" or bt == "acwrite" then
          vim.api.nvim_set_current_win(w)
          return
        end
      end
    end
  end)

  -- Close
  map("q", function() M.close() end)

  -- Help — floating popup (same style as solution explorer)
  map("?", function()
    local KEYS = {
      { key = "<CR>",    desc = "Run test / class or toggle collapse" },
      { key = "<Space>", desc = "Toggle collapse" },
      { key = "r",       desc = "Run node under cursor" },
      { key = "R",       desc = "Run all tests" },
      { key = "f",       desc = "Re-run failed tests" },
      { key = "c",       desc = "Clear results" },
      { key = "e",       desc = "Refresh (re-discover tests)" },
      { key = "<F5>",    desc = "Run all tests" },
      { key = "W",       desc = "Collapse all" },
      { key = "E",       desc = "Expand all" },
      { key = "q",       desc = "Close" },
      { key = "?",       desc = "Toggle this help" },
    }
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    local lines = { " Test Explorer — Keybindings ", "" }
    local width = #lines[1]
    for _, k in ipairs(KEYS) do
      local line = string.format("  %-12s  %s", k.key, k.desc)
      table.insert(lines, line)
      width = math.max(width, #line + 2)
    end
    table.insert(lines, "")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    local ui = vim.api.nvim_list_uis()[1]
    local h  = #lines
    local win = vim.api.nvim_open_win(buf, true, {
      relative  = "editor",
      row       = math.floor((ui.height - h) / 2),
      col       = math.floor((ui.width  - width) / 2),
      width     = width, height = h,
      style     = "minimal", border = "rounded",
      title = " Help ", title_pos = "center",
    })
    local ns = vim.api.nvim_create_namespace("dotnet_te_help")
    vim.api.nvim_buf_add_highlight(buf, ns, "Title", 0, 0, -1)
    for i, k in ipairs(KEYS) do
      vim.api.nvim_buf_add_highlight(buf, ns, "Special", i + 1, 2, 14)
      vim.api.nvim_buf_add_highlight(buf, ns, "Comment", i + 1, 16, -1)
    end
    local close_help = function()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end
    for _, k in ipairs({ "q", "?", "<Esc>" }) do
      vim.api.nvim_buf_set_keymap(buf, "n", k, "", { callback = close_help, noremap = true, silent = true })
    end
  end)
end

-- ── Window management ─────────────────────────────────────────────────────────

local _saved_showtabline = nil

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
  bo.buflisted = false
  bo.filetype  = "dotnet_test_explorer"

  local wo = vim.wo[S.win]
  wo.number         = false
  wo.relativenumber = false
  wo.signcolumn     = "no"
  wo.wrap           = false
  wo.cursorline     = true
  wo.winfixwidth    = true
  wo.winbar         = ""
  wo.statuscolumn   = ""

  vim.api.nvim_buf_set_name(S.buf, "Test Explorer")
  setup_keymaps()
  _saved_showtabline = vim.o.showtabline
  vim.o.showtabline = 0

  vim.api.nvim_create_autocmd("WinClosed", {
    buffer = S.buf,
    once   = true,
    callback = function()
      S.win = nil
      S.buf = nil
      if _saved_showtabline ~= nil then
        vim.o.showtabline = _saved_showtabline
        _saved_showtabline = nil
      end
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
    require("dotnet.commands.init").close_dashboard()
    M.open()
  end
end

return M
