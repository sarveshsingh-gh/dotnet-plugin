-- Central notification + spinner helper.
-- Uses title = "Dotnet" so Noice / nvim-notify render it cleanly.
local M = {}

local function n(msg, level)
  vim.notify(msg, level, { title = "Dotnet" })
end

function M.info(msg)  n(msg, vim.log.levels.INFO)  end
function M.warn(msg)  n(msg, vim.log.levels.WARN)  end
function M.error(msg) n(msg, vim.log.levels.ERROR) end

-- ── Spinner ───────────────────────────────────────────────────────────────────

local FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local _spinners = {}  -- [id] = { timer, frame }

--- Start a cmdline spinner. Returns an id to pass to stop_spinner().
function M.start_spinner(label)
  local id    = tostring(math.random(1e9))
  local state = { frame = 1 }
  local timer = vim.uv.new_timer()
  _spinners[id] = { timer = timer, state = state }

  timer:start(0, 80, vim.schedule_wrap(function()
    if not _spinners[id] then return end
    local f = FRAMES[state.frame]
    vim.api.nvim_echo({ { f .. "  " .. label, "Comment" } }, false, {})
    state.frame = (state.frame % #FRAMES) + 1
  end))

  return id
end

--- Stop spinner and clear the cmdline.
function M.stop_spinner(id)
  local s = _spinners[id]
  if not s then return end
  s.timer:stop()
  s.timer:close()
  _spinners[id] = nil
  -- clear inline — no nested schedule, caller is already in a scheduled context
  vim.api.nvim_echo({ { "" } }, false, {})
end

return M
