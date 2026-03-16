-- dotnet.nvim — Solution Explorer help popup
local M = {}

local KEYS = {
  { key = "<CR>",    desc = "Open file / expand-collapse folder" },
  { key = "<Space>", desc = "Expand/collapse node" },
  { key = "n",       desc = "New item (file from template)" },
  { key = "a",       desc = "Add dependency (package / project ref)" },
  { key = "D",       desc = "Delete / remove node" },
  { key = "r",       desc = "Rename file" },
  { key = "b",       desc = "Build project" },
  { key = "B",       desc = "Build solution" },
  { key = "t",       desc = "Run tests (project)" },
  { key = "T",       desc = "Run tests (solution)" },
  { key = "R",       desc = "Run project" },
  { key = "W",       desc = "Watch project (dotnet watch)" },
  { key = "E",       desc = "Reveal current buffer in explorer" },
  { key = "H",       desc = "Toggle hidden files" },
  { key = "x",       desc = "Stop all background jobs" },
  { key = "/",       desc = "Fuzzy find file in solution" },
  { key = "?",       desc = "Toggle this help" },
  { key = "<F5>",    desc = "Debug — continue" },
  { key = "q",       desc = "Close explorer" },
}

local _win = nil
local _buf = nil

local function close()
  if _win and vim.api.nvim_win_is_valid(_win) then
    vim.api.nvim_win_close(_win, true)
  end
  _win = nil
  _buf = nil
end

function M.toggle()
  if _win and vim.api.nvim_win_is_valid(_win) then
    close()
    return
  end

  _buf = vim.api.nvim_create_buf(false, true)
  vim.bo[_buf].bufhidden = "wipe"
  vim.bo[_buf].filetype  = "dotnet_help"

  local lines = { " Solution Explorer — Keybindings ", "" }
  local width = #lines[1]

  for _, k in ipairs(KEYS) do
    local line = string.format("  %-12s  %s", k.key, k.desc)
    table.insert(lines, line)
    width = math.max(width, #line + 2)
  end
  table.insert(lines, "")

  vim.api.nvim_buf_set_lines(_buf, 0, -1, false, lines)
  vim.bo[_buf].modifiable = false

  local ui    = vim.api.nvim_list_uis()[1]
  local height = #lines
  local row    = math.floor((ui.height - height) / 2)
  local col    = math.floor((ui.width  - width)  / 2)

  _win = vim.api.nvim_open_win(_buf, true, {
    relative = "editor",
    row      = row,
    col      = col,
    width    = width,
    height   = height,
    style    = "minimal",
    border   = "rounded",
    title    = " Help ",
    title_pos = "center",
    noautocmd = true,
  })

  vim.api.nvim_buf_set_keymap(_buf, "n", "q",   "", { callback = close, noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(_buf, "n", "?",   "", { callback = close, noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(_buf, "n", "<Esc>", "", { callback = close, noremap = true, silent = true })

  -- Highlight header
  local ns = vim.api.nvim_create_namespace("dotnet_help")
  vim.api.nvim_buf_add_highlight(_buf, ns, "Title", 0, 0, -1)
  for i, k in ipairs(KEYS) do
    local lnum = i + 1  -- lines[1] is header, lines[2] is blank
    vim.api.nvim_buf_add_highlight(_buf, ns, "Special",  lnum, 2, 14)
    vim.api.nvim_buf_add_highlight(_buf, ns, "Comment",  lnum, 16, -1)
  end
end

return M
