-- Telescope picker: all dotnet jobs — running and completed.
-- gx          → open picker
-- <CR>        → open full log in a split (scrollable)
-- <C-s>       → stop running job
-- <C-x>       → clear all finished logs
local M = {}

local function open_log_buf(lines, title)
  -- reuse existing log window if open
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.b[buf]._dotnet_log then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_set_current_win(win)
      pcall(vim.api.nvim_win_set_cursor, win, { math.max(1, #lines), 0 })
      return
    end
  end
  vim.cmd("botright 20split")
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, buf)
  vim.b[buf]._dotnet_log = true
  vim.bo[buf].buftype    = "nofile"
  vim.bo[buf].bufhidden  = "wipe"
  vim.bo[buf].filetype   = "log"
  vim.bo[buf].swapfile   = false
  vim.api.nvim_buf_set_name(buf, title or "Dotnet Log")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  pcall(vim.api.nvim_win_set_cursor, win, { math.max(1, #lines), 0 })
  -- q closes the log window
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
end

local function get_lines(e)
  if e.buf and vim.api.nvim_buf_is_valid(e.buf) then
    local n = vim.api.nvim_buf_line_count(e.buf)
    return vim.api.nvim_buf_get_lines(e.buf, math.max(0, n - 500), n, false)
  elseif e.lines and #e.lines > 0 then
    return e.lines
  end
  return { "(no output captured)" }
end

function M.open()
  local runner = require("dotnet.core.runner")

  local ok_p,  pickers    = pcall(require, "telescope.pickers")
  local ok_f,  finders    = pcall(require, "telescope.finders")
  local ok_c,  conf       = pcall(require, "telescope.config")
  local ok_a,  actions    = pcall(require, "telescope.actions")
  local ok_as, act_state  = pcall(require, "telescope.actions.state")
  local ok_pr, previewers = pcall(require, "telescope.previewers")
  if not (ok_p and ok_f and ok_c and ok_a and ok_as and ok_pr) then return end

  local function make_entries()
    local entries = {}
    for _, j in ipairs(runner.active_jobs()) do
      table.insert(entries, {
        kind   = "running",
        label  = j.label,
        buf    = j.buf,
        job_id = j.job_id,
        status = "running",
        time   = "",
        lines  = nil,
      })
    end
    local log = runner.job_log()
    for i = #log, 1, -1 do
      local l = log[i]
      table.insert(entries, {
        kind    = "log",
        label   = l.label,
        buf     = nil,
        job_id  = nil,
        status  = l.status,
        time    = l.time,
        lines   = l.lines,
        log_idx = i,
      })
    end
    return entries
  end

  local entries = make_entries()
  if #entries == 0 then
    vim.notify("[dotnet] No jobs (running or recent)", vim.log.levels.INFO)
    return
  end

  local previewer = previewers.new_buffer_previewer({
    title = "Output",
    define_preview = function(self, entry)
      local pbuf  = self.state.bufnr
      local lines = get_lines(entry.value)
      while #lines > 0 and vim.trim(lines[#lines]) == "" do table.remove(lines) end
      vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, lines)
      vim.bo[pbuf].filetype = "log"
      local pwin = self.state.winid
      if pwin and vim.api.nvim_win_is_valid(pwin) then
        pcall(vim.api.nvim_win_set_cursor, pwin, { math.max(1, #lines), 0 })
      end
    end,
  })

  pickers.new({}, {
    prompt_title = " Dotnet Jobs  [<CR>=open log  <C-s>=stop  <C-x>=clear]",
    finder = finders.new_table({
      results     = entries,
      entry_maker = function(e)
        local icon = e.kind == "running" and "  "
                  or (e.status == "ok" and " " or " ")
        local time = e.time ~= "" and ("[" .. e.time .. "] ") or ""
        return {
          value   = e,
          display = icon .. time .. e.label,
          ordinal = e.label,
        }
      end,
    }),
    sorter    = conf.values.generic_sorter({}),
    previewer = previewer,
    attach_mappings = function(prompt_bufnr, map)
      -- CR: open full log in a split
      actions.select_default:replace(function()
        local sel = act_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if not sel then return end
        local e     = sel.value
        local lines = get_lines(e)
        while #lines > 0 and vim.trim(lines[#lines]) == "" do table.remove(lines) end
        open_log_buf(lines, e.label)
      end)

      -- C-s: stop running job (without opening log)
      map({ "i", "n" }, "<C-s>", function()
        local sel = act_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if not sel then return end
        local e = sel.value
        if e.kind == "running" and e.job_id then
          runner.stop(e.job_id)
          vim.notify("[dotnet] Stopped: " .. e.label, vim.log.levels.INFO)
        end
      end)

      -- C-x: clear finished log
      map({ "i", "n" }, "<C-x>", function()
        actions.close(prompt_bufnr)
        runner.clear_log()
        vim.notify("[dotnet] Job log cleared", vim.log.levels.INFO)
      end)

      return true
    end,
  }):find()
end

return M
