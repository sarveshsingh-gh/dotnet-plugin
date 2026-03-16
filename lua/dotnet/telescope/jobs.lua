-- Telescope picker: list and stop running dotnet jobs.
local M = {}

function M.open()
  local runner = require("dotnet.core.runner")
  local jobs   = runner.active_jobs()

  if #jobs == 0 then
    vim.notify("[dotnet] No running processes", vim.log.levels.INFO)
    return
  end

  local ok_p,  pickers    = pcall(require, "telescope.pickers")
  local ok_f,  finders    = pcall(require, "telescope.finders")
  local ok_c,  conf       = pcall(require, "telescope.config")
  local ok_a,  actions    = pcall(require, "telescope.actions")
  local ok_as, act_state  = pcall(require, "telescope.actions.state")
  local ok_pr, previewers = pcall(require, "telescope.previewers")
  if not (ok_p and ok_f and ok_c and ok_a and ok_as and ok_pr) then return end

  local previewer = previewers.new_buffer_previewer({
    title = "Output",
    define_preview = function(self, entry)
      local pbuf = self.state.bufnr
      local src  = entry.value.buf
      if src and vim.api.nvim_buf_is_valid(src) then
        local n      = vim.api.nvim_buf_line_count(src)
        local lines  = vim.api.nvim_buf_get_lines(src, math.max(0, n - 200), n, false)
        vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, lines)
        vim.bo[pbuf].filetype = "log"
        local pwin = self.state.winid
        if pwin and vim.api.nvim_win_is_valid(pwin) then
          pcall(vim.api.nvim_win_set_cursor, pwin, { #lines, 0 })
        end
      else
        vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, { "(no output buffer)" })
      end
    end,
  })

  pickers.new({}, {
    prompt_title = "Running Processes  [Enter = stop]",
    finder = finders.new_table({
      results     = jobs,
      entry_maker = function(j)
        return { value = j, display = j.cmd, ordinal = j.cmd }
      end,
    }),
    sorter    = conf.values.generic_sorter({}),
    previewer = previewer,
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local sel = act_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if sel then runner.stop(sel.value.job_id) end
      end)
      return true
    end,
  }):find()
end

return M
