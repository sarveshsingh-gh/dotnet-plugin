-- Central notification helper.
-- title = "Dotnet" → Noice renders it as a titled popup.
local M = {}

local function n(msg, level)
  vim.notify(msg, level, { title = "Dotnet" })
end

function M.info(msg)  n(msg, vim.log.levels.INFO)  end
function M.warn(msg)  n(msg, vim.log.levels.WARN)  end
function M.error(msg) n(msg, vim.log.levels.ERROR) end

function M.ok(msg)   n(" " .. msg, vim.log.levels.INFO)  end
function M.fail(msg) n(" " .. msg, vim.log.levels.ERROR) end

-- ── Spinner (cmdline) ─────────────────────────────────────────────────────────

local FRAMES   = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local _spinners = {}

function M.start_spinner(label)
  local id    = tostring(math.random(1e9))
  local state = { frame = 1 }
  local timer = vim.uv.new_timer()
  _spinners[id] = { timer = timer, state = state }
  timer:start(0, 80, vim.schedule_wrap(function()
    if not _spinners[id] then return end
    vim.api.nvim_echo({ { FRAMES[state.frame] .. "  " .. label, "Comment" } }, false, {})
    state.frame = (state.frame % #FRAMES) + 1
  end))
  return id
end

function M.stop_spinner(id)
  local s = _spinners[id]
  if not s then return end
  s.timer:stop()
  s.timer:close()
  _spinners[id] = nil
  vim.api.nvim_echo({ { "" } }, false, {})
end

return M
