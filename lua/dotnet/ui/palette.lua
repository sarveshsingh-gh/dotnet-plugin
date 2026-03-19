-- Command Palette — Telescope picker over all registered dotnet commands.
local M = {}

function M.open(opts)
  opts = opts or {}

  local ok_p,  pickers   = pcall(require, "telescope.pickers")
  local ok_f,  finders   = pcall(require, "telescope.finders")
  local ok_c,  conf      = pcall(require, "telescope.config")
  local ok_a,  actions   = pcall(require, "telescope.actions")
  local ok_as, act_state = pcall(require, "telescope.actions.state")
  if not (ok_p and ok_f and ok_c and ok_a and ok_as) then
    -- Fallback to vim.ui.select
    local cmds = require("dotnet.commands.init").all()
    vim.ui.select(cmds, {
      prompt      = "Dotnet:",
      format_item = function(c) return (c.icon or "") .. c.desc .. "  [" .. c.category .. "]" end,
    }, function(c)
      if c then
        require("dotnet.commands.init").close_dashboard()
        c.run()
      end
    end)
    return
  end

  local cmds = require("dotnet.commands.init").all()

  -- Pad string to `w` display columns using strdisplaywidth
  local function rpad(s, w)
    local dw = vim.fn.strdisplaywidth(s)
    return dw < w and (s .. string.rep(" ", w - dw)) or s
  end

  pickers.new({}, {
    prompt_title = " Dotnet",
    finder = finders.new_table({
      results     = cmds,
      entry_maker = function(c)
        local icon_s = rpad(c.icon or "  ", 3)   -- nerd font = 2 cols + 1 space
        local desc_s = rpad(c.desc, 46)
        local cat_s  = rpad("[" .. (c.category or "") .. "]", 12)
        local key_s  = c.key or ""
        local full   = icon_s .. desc_s .. cat_s .. "  " .. key_s

        -- highlights use byte offsets into `full`
        local cat_b = #icon_s + #desc_s
        local key_b = cat_b + #cat_s + 2
        return {
          value   = c,
          display = function()
            return full, {
              { { cat_b, cat_b + #cat_s },       "Type"    },
              { { key_b, key_b + #key_s },       "Comment" },
            }
          end,
          ordinal = c.desc .. " " .. (c.category or ""),
        }
      end,
    }),
    sorter  = conf.values.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local sel = act_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if sel then
          vim.schedule(function()
            require("dotnet.commands.init").close_dashboard()
            sel.value.run()
          end)
        end
      end)
      return true
    end,
  }):find()
end

return M
