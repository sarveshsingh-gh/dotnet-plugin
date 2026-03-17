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

  pickers.new({}, {
    prompt_title = " Dotnet",
    finder = finders.new_table({
      results     = cmds,
      entry_maker = function(c)
        local icon = c.icon or "  "
        local desc = string.format("%-30s", c.desc)
        local cat  = string.format("%-10s", "[" .. (c.category or "") .. "]")
        local key  = c.key or ""
        local full = icon .. desc .. "  " .. cat .. "  " .. key

        local cat_start = #icon + #desc + 2
        local key_start = cat_start + #cat + 2
        return {
          value   = c,
          display = function()
            return full, {
              { { cat_start, cat_start + #cat }, "Type"    },
              { { key_start, key_start + #key }, "Comment" },
            }
          end,
          ordinal = (c.category or "") .. " " .. c.desc,
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
