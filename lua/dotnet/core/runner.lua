-- Async dotnet CLI runner with job tracking.
-- bg()   → background job (build/test/restore) — no window, notify on done
-- term() → terminal job  (run/watch)            — opens a terminal buffer
local M = {}

local _jobs = {}    -- [job_id] = { label, buf, pid, cmd }        active
local _log  = {}    -- list of { label, status, lines, time }     completed (capped at 50)

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function read_cmdline(pid)
  local f = io.open("/proc/" .. tostring(pid) .. "/cmdline", "r")
  if not f then return nil end
  local s = f:read("*a"); f:close()
  return s:gsub("%z", " "):gsub("%s+$", "")
end

local function untrack(job_id, status, lines)
  local j = _jobs[job_id]
  if j then
    table.insert(_log, {
      label  = j.label,
      status = status or "done",
      lines  = lines or {},
      time   = os.date("%H:%M:%S"),
    })
    if #_log > 50 then table.remove(_log, 1) end
  end
  _jobs[job_id] = nil
end

function M.job_log() return _log end
function M.clear_log() _log = {} end

-- ── Quickfix parser ───────────────────────────────────────────────────────────
-- Parses dotnet build/test stdout into a quickfix list.
-- Pattern: /path/file.cs(line,col): error|warning CSxxxx: message
local QF_PATTERN = "^(.-)%((%d+),(%d+)%):%s+(%a+)%s+(CS%d+):%s+(.+)$"

local function parse_qf(lines)
  local items = {}
  for _, l in ipairs(lines) do
    local file, row, col, severity, code, msg = l:match(QF_PATTERN)
    if file then
      table.insert(items, {
        filename = vim.trim(file),
        lnum     = tonumber(row),
        col      = tonumber(col),
        type     = severity:sub(1,1):upper(),  -- E / W
        text     = code .. ": " .. msg,
      })
    end
  end
  return items
end

-- ── Background job ────────────────────────────────────────────────────────────

--- Run a dotnet command in background (no terminal window).
-- opts: { cwd, label, quickfix, on_exit }
function M.bg(args, opts)
  opts = opts or {}
  local label   = opts.label or table.concat(args, " ")
  local stdout  = {}
  local stderr  = {}
  local notify  = require("dotnet.notify")
  local spin_id = notify.start_spinner(label)

  local job_id = vim.fn.jobstart(args, {
    cwd        = opts.cwd,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout  = function(_, data) vim.list_extend(stdout, data) end,
    on_stderr  = function(_, data) vim.list_extend(stderr, data) end,
    on_exit    = function(id, code)
      vim.schedule(function()
        notify.stop_spinner(spin_id)
        local all_out = vim.list_extend(vim.deepcopy(stdout), stderr)
        local status  = code == 0 and "ok" or "failed"
        untrack(id, status, all_out)
        if code ~= 0 then
          notify.fail(label .. " — press gx to see log")
        else
          if opts.notify_success ~= false then
            notify.ok(label)
          end
        end

        -- Populate quickfix if requested
        if opts.quickfix then
          local all = vim.list_extend(vim.deepcopy(stdout), stderr)
          local qf  = parse_qf(all)
          vim.fn.setqflist({}, "r", { title = label, items = qf })
          if #qf > 0 then
            vim.cmd("copen")
            require("dotnet.notify").warn(#qf .. " issue(s) → quickfix")
          end
        end

        if opts.on_exit then opts.on_exit(code, stdout, stderr) end
      end)
    end,
  })

  if job_id > 0 then
    local ok, pid = pcall(vim.fn.jobpid, job_id)
    _jobs[job_id] = { label = label, buf = nil, pid = ok and pid or nil, cmd = args }
  end

  return job_id
end

-- ── Terminal job ──────────────────────────────────────────────────────────────

--- Run a dotnet command in a terminal split (bottom, NvChad-compatible).
-- opts: { cwd, label, on_exit }
function M.term(args, opts)
  opts = opts or {}
  local label = opts.label or table.concat(args, " ")

  -- Build command string (cd to cwd first so termopen cwd option isn't needed)
  local cmd_str = table.concat(vim.tbl_map(vim.fn.shellescape, args), " ")
  if opts.cwd then
    cmd_str = "cd " .. vim.fn.shellescape(opts.cwd) .. " && " .. cmd_str
  end

  -- Use NvChad's terminal — handles buflisted, winopts, splits correctly
  local ok, nvterm = pcall(require, "nvchad.term")
  if ok then
    nvterm.new({ cmd = cmd_str, pos = "bo sp", size = 0.35 })
    local buf = vim.api.nvim_get_current_buf()
    local job_id = vim.b[buf].terminal_job_id or -1
    if job_id > 0 then
      local okp, pid = pcall(vim.fn.jobpid, job_id)
      _jobs[job_id] = { label = label, buf = buf, pid = okp and pid or nil, cmd = args }
      vim.keymap.set("n", "x", function() M.stop(job_id) end, { buffer = buf, silent = true })
    end
    return job_id, buf
  end

  -- Fallback: raw split + termopen
  local buf = vim.api.nvim_create_buf(false, true)
  vim.cmd("bo sp")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.bo[buf].buflisted = false
  vim.api.nvim_win_set_height(win, math.floor(vim.o.lines * 0.35))

  local job_id = vim.fn.termopen({ vim.o.shell, "-c", cmd_str }, {
    on_exit = function(id, code)
      vim.schedule(function()
        untrack(id)
        if opts.on_exit then opts.on_exit(code) end
      end)
    end,
  })

  if job_id > 0 then
    local okp, pid = pcall(vim.fn.jobpid, job_id)
    _jobs[job_id] = { label = label, buf = buf, pid = okp and pid or nil, cmd = args }
    vim.keymap.set("n", "x", function() M.stop(job_id) end, { buffer = buf, silent = true })
  end

  return job_id, buf
end

-- ── Job management ────────────────────────────────────────────────────────────

function M.stop(job_id)
  pcall(vim.fn.jobstop, job_id)
  untrack(job_id)
end

function M.stop_all()
  local stopped = 0
  for id in pairs(_jobs) do
    pcall(vim.fn.jobstop, id)
    stopped = stopped + 1
  end
  _jobs = {}
  -- Also stop any other terminal buffers with active jobs
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "terminal" then
      local jid = vim.b[buf].terminal_job_id
      if jid then pcall(vim.fn.jobstop, jid); stopped = stopped + 1 end
    end
  end
  require("dotnet.notify").info("Stopped " .. stopped .. " process(es)")
end

--- Return list of active jobs for the jobs picker.
function M.active_jobs()
  local result = {}
  -- Our tracked jobs
  for id, j in pairs(_jobs) do
    local ok, pid = pcall(vim.fn.jobpid, id)
    if ok and pid then
      table.insert(result, { job_id = id, label = j.label, buf = j.buf,
                             cmd = read_cmdline(pid) or j.label })
    end
  end
  -- Any terminal buffer not tracked
  local seen = {}
  for _, j in pairs(_jobs) do seen[j.buf] = true end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if not seen[buf] and vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "terminal" then
      local jid = vim.b[buf].terminal_job_id
      if jid then
        local ok2, pid = pcall(vim.fn.jobpid, jid)
        local cmd = (ok2 and pid and read_cmdline(pid)) or vim.api.nvim_buf_get_name(buf)
        table.insert(result, { job_id = jid, label = cmd, buf = buf, cmd = cmd })
      end
    end
  end
  return result
end

-- ── High-level commands ───────────────────────────────────────────────────────

function M.build(target, opts)
  opts = opts or {}
  return M.bg({ "dotnet", "build", target }, vim.tbl_extend("force", {
    cwd   = vim.fn.fnamemodify(target, ":h"),
    label = "Build " .. vim.fn.fnamemodify(target, ":t"),
  }, opts))
end

function M.build_qf(target, opts)
  opts = opts or {}
  return M.bg({ "dotnet", "build", target }, vim.tbl_extend("force", {
    cwd      = vim.fn.fnamemodify(target, ":h"),
    label    = "Build " .. vim.fn.fnamemodify(target, ":t"),
    quickfix = true,
  }, opts))
end

function M.restore(target, opts)
  opts = opts or {}
  return M.bg({ "dotnet", "restore", target }, vim.tbl_extend("force", {
    cwd   = vim.fn.fnamemodify(target, ":h"),
    label = "Restore",
  }, opts))
end

function M.clean(target, opts)
  opts = opts or {}
  return M.bg({ "dotnet", "clean", target }, vim.tbl_extend("force", {
    cwd   = vim.fn.fnamemodify(target, ":h"),
    label = "Clean",
  }, opts))
end

function M.run(proj_path, opts)
  opts = opts or {}
  local cmd = { "dotnet", "run", "--project", proj_path }
  if opts.profile then vim.list_extend(cmd, { "--launch-profile", opts.profile }) end
  return M.term(cmd, vim.tbl_extend("force", opts, {
    label = "Run " .. vim.fn.fnamemodify(proj_path, ":t:r"),
    cwd   = vim.fn.fnamemodify(proj_path, ":h"),
  }))
end

function M.watch(proj_path, opts)
  opts = opts or {}
  return M.term({ "dotnet", "watch", "--project", proj_path }, vim.tbl_extend("force", opts, {
    label = "Watch " .. vim.fn.fnamemodify(proj_path, ":t:r"),
    cwd   = vim.fn.fnamemodify(proj_path, ":h"),
  }))
end

function M.test(target, opts)
  opts = opts or {}
  return M.bg({ "dotnet", "test", target }, vim.tbl_extend("force", {
    cwd   = vim.fn.fnamemodify(target, ":h"),
    label = "Test " .. vim.fn.fnamemodify(target, ":t"),
  }, opts))
end

function M.test_qf(target, opts)
  opts = opts or {}
  return M.bg({ "dotnet", "test", target }, vim.tbl_extend("force", {
    cwd      = vim.fn.fnamemodify(target, ":h"),
    label    = "Test " .. vim.fn.fnamemodify(target, ":t"),
    quickfix = true,
  }, opts))
end

return M
