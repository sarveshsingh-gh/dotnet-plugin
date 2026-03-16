-- Annotate .cs buffers with test results (gutter signs + eol virtual text).
-- Called after TRX parsing completes in test_explorer.
local M = {}

local ns = vim.api.nvim_create_namespace("dotnet_test_signs")

vim.fn.sign_define("DotnetTestPassed",  { text = "✓", texthl = "DotnetTestPassed"  })
vim.fn.sign_define("DotnetTestFailed",  { text = "✗", texthl = "DotnetTestFailed"  })
vim.fn.sign_define("DotnetTestSkipped", { text = "○", texthl = "DotnetTestSkipped" })
vim.fn.sign_define("DotnetTestRunning", { text = "●", texthl = "DotnetTestRunning" })

local SIGN = {
  passed  = "DotnetTestPassed",
  failed  = "DotnetTestFailed",
  skipped = "DotnetTestSkipped",
  running = "DotnetTestRunning",
}
local VT = {
  passed  = { " ✓ Passed",  "DotnetTestPassed"  },
  failed  = { " ✗ Failed",  "DotnetTestFailed"  },
  skipped = { " ○ Skipped", "DotnetTestSkipped" },
  running = { " ● Running", "DotnetTestRunning" },
}

-- Clear all dotnet test signs + extmarks from all cs buffers.
function M.clear()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "cs" then
      vim.fn.sign_unplace("dotnet_tests", { buffer = buf })
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
  end
end

-- Find 1-based line number of a test method in a buffer.
local function find_method_line(bufnr, method_name)
  local pat = vim.pesc(method_name) .. "%s*%("
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:match(pat) then return i end
  end
end

-- Annotate all loaded .cs buffers with results.
-- results: { ["Namespace.Class.Method"] = "passed"|"failed"|"skipped" }
function M.annotate(results)
  M.clear()
  local cs_bufs = vim.tbl_filter(function(b)
    return vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == "cs"
  end, vim.api.nvim_list_bufs())
  if #cs_bufs == 0 then return end

  for fqn, state in pairs(results) do
    local parts = vim.split(fqn, "%.")
    local method = parts[#parts]
    local sign   = SIGN[state]
    local vt     = VT[state]
    if not sign then goto continue end

    for _, buf in ipairs(cs_bufs) do
      local lnum = find_method_line(buf, method)
      if lnum then
        vim.fn.sign_place(0, "dotnet_tests", sign, buf, { lnum = lnum, priority = 110 })
        vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, {
          virt_text     = { vt },
          virt_text_pos = "eol",
          priority      = 110,
        })
      end
    end
    ::continue::
  end
end

-- Mark all methods in a buffer as running (called when tests start).
function M.mark_running(proj_path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if not vim.api.nvim_buf_is_loaded(buf) or vim.bo[buf].filetype ~= "cs" then
      goto skip
    end
    local file = vim.api.nvim_buf_get_name(buf)
    local dir  = proj_path and (vim.fn.fnamemodify(proj_path, ":h") .. "/") or ""
    if proj_path and file:sub(1, #dir) ~= dir then goto skip end
    -- Place running marker on [Fact]/[Test]/[Theory] attribute lines
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    vim.fn.sign_unplace("dotnet_tests", { buffer = buf })
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for i, line in ipairs(lines) do
      if line:match("%[Fact%]") or line:match("%[Test%]") or line:match("%[Theory%]")
          or line:match("%[TestMethod%]") then
        vim.fn.sign_place(0, "dotnet_tests", "DotnetTestRunning", buf, { lnum = i, priority = 110 })
      end
    end
    ::skip::
  end
  vim.cmd("redraw")
end

return M
