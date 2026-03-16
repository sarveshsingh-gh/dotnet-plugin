-- Telescope picker: fuzzy find files in the solution, reveal in explorer.
local M = {}

function M.open(sln_path, on_select)
  local solution = require("dotnet.core.solution")
  local project  = require("dotnet.core.project")
  local sln      = sln_path or solution.find()
  if not sln then
    require("dotnet.notify").warn("No solution found")
    return
  end

  -- Collect all files across all projects
  local files = {}
  for _, pp in ipairs(solution.projects(sln)) do
    local proj_dir = vim.fn.fnamemodify(pp, ":h")
    for _, e in ipairs(project.scan_dir(proj_dir, false)) do
      if not e.is_dir then
        table.insert(files, {
          path = e.path,
          rel  = e.path:sub(#proj_dir + 2),
          proj = vim.fn.fnamemodify(pp, ":t:r"),
        })
      end
    end
  end

  if #files == 0 then
    require("dotnet.notify").warn("No files found in solution")
    return
  end

  local ok_p,  pickers   = pcall(require, "telescope.pickers")
  local ok_f,  finders   = pcall(require, "telescope.finders")
  local ok_c,  conf      = pcall(require, "telescope.config")
  local ok_a,  actions   = pcall(require, "telescope.actions")
  local ok_as, act_state = pcall(require, "telescope.actions.state")
  if not (ok_p and ok_f and ok_c and ok_a and ok_as) then return end

  pickers.new({}, {
    prompt_title = "Solution Files",
    finder = finders.new_table({
      results     = files,
      entry_maker = function(f)
        local display = f.proj .. "  " .. f.rel
        return { value = f.path, display = display, ordinal = display }
      end,
    }),
    sorter = conf.values.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local sel = act_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if sel then
          if on_select then
            on_select(sel.value)
          else
            vim.cmd("edit " .. vim.fn.fnameescape(sel.value))
          end
        end
      end)
      return true
    end,
  }):find()
end

return M
