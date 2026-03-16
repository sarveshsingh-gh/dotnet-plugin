-- VS-style DAP breakpoint signs and highlight colours.
local M = {}

function M.setup(cfg)
  cfg = cfg or {}
  local s = cfg.signs or {}

  local function sign(name, icon_cfg, linehl)
    vim.fn.sign_define(name, {
      text   = icon_cfg.text,
      texthl = name,
      linehl = linehl or "",
      numhl  = "",
    })
    vim.api.nvim_set_hl(0, name, { fg = icon_cfg.color })
  end

  local bp  = s.breakpoint          or { text = "●", color = "#E51400" }
  local bpc = s.breakpoint_cond     or { text = "◆", color = "#FF8C00" }
  local bpr = s.breakpoint_rejected or { text = "○", color = "#6D8086" }
  local lp  = s.logpoint            or { text = "◉", color = "#61AFEF" }
  local st  = s.stopped             or { text = "▶", color = "#FFD700", linehl_bg = "#3B3800" }

  sign("DapBreakpoint",          bp)
  sign("DapBreakpointCondition", bpc)
  sign("DapBreakpointRejected",  bpr)
  sign("DapLogPoint",            lp)
  sign("DapStopped",             st, "DapStoppedLine")

  vim.api.nvim_set_hl(0, "DapStoppedLine", { bg = st.linehl_bg or "#3B3800" })
end

return M
