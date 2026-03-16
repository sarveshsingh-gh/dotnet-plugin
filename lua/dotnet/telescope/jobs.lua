-- Telescope picker: all dotnet jobs — running and completed.
-- gx (or jobs.list): open picker
-- <Enter> on running  → stop job
-- <Enter> on finished → remove from log
-- <C-x>              → clear all finished logs
local M = {}

function M.open()
  local runner = require("dotnet.core.runner")

  local ok_p,  pickers    = pcall(require, "telescope.pickers")
  local ok_f,  finders    = pcall(require, "telescope.finders")
  local ok_c,  conf       = pcall(require, "telescope.config")
  local ok_a,  actions    = pcall(require, "telescope.actions")
  local ok_as, act_state  = pcall(require, "telescope.actions.state")
  local ok_pr, previewers = pcall(require, "telescope.previewers")
  if not (ok_p and ok_f and ok_c and ok_a and ok_as and ok_pr) then return end

  -- Build combined entry list
  local function make_entries()
    local entries = {}

    -- Active (running) jobs
    for _, j in ipairs(runner.active_jobs()) do
      table.insert(entries, {
        kind    = "running",
        label   = j.label,
        display = "  " .. j.label,
        lines   = nil,    -- read from terminal buf live
        buf     = j.buf,
        job_id  = j.job_id,
        status  = "running",
        time    = "",
      })
    end

    -- Completed (log) — newest first
    local log = runner.job_log()
    for i = #log, 1, -1 do
      local l = log[i]
      local icon = l.status == "ok" and " " or " "
      table.insert(entries, {
        kind    = "log",
        label   = l.label,
        display = icon .. "[" .. l.time .. "] " .. l.label,
        lines   = l.lines,
        buf     = nil,
        job_id  = nil,
        status  = l.status,
        time    = l.time,
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
      local lines = {}
      if entry.value.buf and vim.api.nvim_buf_is_valid(entry.value.buf) then
        -- terminal buffer — grab last 300 lines
        local n = vim.api.nvim_buf_line_count(entry.value.buf)
        lines   = vim.api.nvim_buf_get_lines(entry.value.buf, math.max(0, n - 300), n, false)
      elseif entry.value.lines then
        lines = entry.value.lines
      else
        lines = { "(no output captured)" }
      end
      -- strip empty trailing lines
      while #lines > 0 and vim.trim(lines[#lines]) == "" do
        table.remove(lines)
      end
      vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, lines)
      vim.bo[pbuf].filetype = "log"
      local pwin = self.state.winid
      if pwin and vim.api.nvim_win_is_valid(pwin) then
        pcall(vim.api.nvim_win_set_cursor, pwin, { math.max(1, #lines), 0 })
      end
    end,
  })

  pickers.new({}, {
    prompt_title = " Dotnet Jobs  [<CR>=stop/dismiss  <C-x>=clear log]",
    finder = finders.new_table({
      results     = entries,
      entry_maker = function(e)
        return {
          value   = e,
          display = e.display,
          ordinal = e.label,
        }
      end,
    }),
    sorter    = conf.values.generic_sorter({}),
    previewer = previewer,
    attach_mappings = function(prompt_bufnr, map)
      -- Enter: stop running job, or dismiss completed entry
      actions.select_default:replace(function()
        local sel = act_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if not sel then return end
        local e = sel.value
        if e.kind == "running" and e.job_id then
          runner.stop(e.job_id)
          vim.notify("[dotnet] Stopped: " .. e.label, vim.log.levels.INFO)
        end
        -- for log entries: just closes (dismissed)
      end)

      -- C-x: clear all finished logs
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
