-- dotnet.nvim — HTTP / REST client for .http / .rest files
-- Supports the VS Code REST Client / JetBrains format:
--   METHOD URL
--   Header: value
--
--   body
--   ### separator between requests
--   @var = value  declarations resolved as {{var}}
local cmd    = require("dotnet.commands.init")
local notify = require("dotnet.notify")

local function reg(id, def) cmd.register(id, vim.tbl_extend("force", { category = "http" }, def)) end

-- ── Parser ────────────────────────────────────────────────────────────────────

local function parse_vars(lines)
  local vars = {}
  for _, l in ipairs(lines) do
    local k, v = l:match("^@(%w[%w_]*)%s*=%s*(.+)$")
    if k then vars[k] = vim.trim(v) end
  end
  return vars
end

local function subst(text, vars)
  return (text:gsub("{{([%w_]+)}}", function(k)
    return vars[k] or ("{{" .. k .. "}}")
  end))
end

-- Return 1-indexed [start, end] lines of the request block under cursor_line.
local function find_block(lines, cursor_line)
  local start_l, end_l = 1, #lines
  for i = cursor_line, 1, -1 do
    if lines[i]:match("^###") then start_l = i + 1; break end
  end
  for i = cursor_line + 1, #lines do
    if lines[i]:match("^###") then end_l = i - 1; break end
  end
  return start_l, end_l
end

-- Parse block lines into { method, url, headers=[{name,value}], body }
local function parse_request(block, vars)
  local i = 1
  local method, url
  while i <= #block do
    local l = vim.trim(block[i])
    -- Skip comment/blank/variable-declaration lines before the method line
    if l ~= "" and not l:match("^#") and not l:match("^@") then
      method, url = l:match("^(%u+)%s+(%S+)")
      if method then url = subst(url, vars); i = i + 1; break end
    end
    i = i + 1
  end
  if not method then return nil end

  local headers = {}
  while i <= #block do
    local l = block[i]
    if l == "" then i = i + 1; break end
    local name, val = l:match("^([^:]+):%s*(.+)$")
    if name then
      table.insert(headers, {
        name  = subst(vim.trim(name), vars),
        value = subst(vim.trim(val),  vars),
      })
    end
    i = i + 1
  end

  local body_lines = {}
  while i <= #block do
    table.insert(body_lines, subst(block[i], vars))
    i = i + 1
  end
  while #body_lines > 0 and body_lines[#body_lines] == "" do table.remove(body_lines) end

  return {
    method  = method,
    url     = url,
    headers = headers,
    body    = #body_lines > 0 and table.concat(body_lines, "\n") or nil,
  }
end

local CURL = vim.fn.has("win32") == 1 and "curl.exe" or "curl"

local function build_curl(req)
  local args = { CURL, "-s", "-i", "-X", req.method }
  for _, h in ipairs(req.headers) do
    table.insert(args, "-H")
    table.insert(args, h.name .. ": " .. h.value)
  end
  if req.body then
    table.insert(args, "-d")
    table.insert(args, req.body)
  end
  table.insert(args, req.url)
  return args
end

-- ── Runner ────────────────────────────────────────────────────────────────────

local function run_request_at_cursor()
  local lines      = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cursor     = vim.api.nvim_win_get_cursor(0)[1]
  local vars       = parse_vars(lines)
  local sl, el     = find_block(lines, cursor)
  local block      = vim.list_slice(lines, sl, el)
  local req        = parse_request(block, vars)

  if not req then
    notify.warn("No HTTP request found at cursor")
    return
  end

  local out = {}
  vim.fn.jobstart(build_curl(req), {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data) vim.list_extend(out, data) end,
    on_stderr = function(_, data) vim.list_extend(out, data) end,
    on_exit   = function(_, code)
      vim.schedule(function()
        while #out > 0 and out[#out] == "" do table.remove(out) end
        if #out == 0 then
          out = { code == 0 and "(empty response)" or "(request failed — check URL / network)" }
        end

        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
        vim.bo[buf].filetype   = "http"
        vim.bo[buf].modifiable = false
        vim.bo[buf].bufhidden  = "wipe"

        -- Open in a right vertical split
        vim.cmd("botright vsplit")
        local win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(win, buf)
        vim.api.nvim_win_set_width(win, math.floor(vim.o.columns * 0.45))
        vim.wo[win].number         = false
        vim.wo[win].relativenumber = false
        vim.wo[win].signcolumn     = "no"
        vim.wo[win].wrap           = true
        vim.keymap.set("n", "q",     "<cmd>close<cr>", { buffer = buf, silent = true })
        vim.keymap.set("n", "<esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
      end)
    end,
  })
end

-- ── Palette commands ──────────────────────────────────────────────────────────

reg("http.run_request", {
  icon = "󰒆 ",
  desc = "HTTP: Run request at cursor",
  run  = run_request_at_cursor,
})

reg("http.new_file", {
  icon = "󰐅 ",
  desc = "HTTP: New .http request file",
  run  = function()
    vim.ui.input({ prompt = "File name (without .http): ", default = "requests" }, function(name)
      if not name or name == "" then return end
      local path = vim.fn.getcwd() .. "/" .. name .. ".http"
      if vim.fn.filereadable(path) == 0 then
        vim.fn.writefile({
          "### GET example",
          "GET https://jsonplaceholder.typicode.com/todos/1",
          "Accept: application/json",
          "",
          "###",
          "",
          "### POST example",
          "POST https://jsonplaceholder.typicode.com/todos",
          "Content-Type: application/json",
          "",
          "{",
          '  "title": "my task",',
          '  "completed": false',
          "}",
          "",
          "###",
        }, path)
      end
      vim.cmd("edit " .. vim.fn.fnameescape(path))
    end)
  end,
})

-- ── Buffer keymaps for .http / .rest files ───────────────────────────────────

vim.api.nvim_create_autocmd({ "BufEnter", "BufNew" }, {
  pattern  = { "*.http", "*.rest" },
  callback = function(ev)
    vim.keymap.set("n", "<CR>", run_request_at_cursor,
      { buffer = ev.buf, desc = "HTTP: Run request at cursor", silent = true })
  end,
})
