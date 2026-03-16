-- Central notification helper.
-- Uses title = "Dotnet" so Noice / nvim-notify render it cleanly.
local M = {}

local function n(msg, level)
  vim.notify(msg, level, { title = "Dotnet" })
end

function M.info(msg)  n(msg, vim.log.levels.INFO)  end
function M.warn(msg)  n(msg, vim.log.levels.WARN)  end
function M.error(msg) n(msg, vim.log.levels.ERROR) end

return M
