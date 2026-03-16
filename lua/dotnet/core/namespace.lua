-- Compute and patch C# namespace declarations.
local M = {}

--- Derive the correct namespace for a .cs file.
-- Uses <RootNamespace> from the .csproj, falls back to project name.
-- Appends dot-separated sub-folder path relative to the project root.
function M.compute(proj_path, file_path)
  local root_ns = vim.fn.fnamemodify(proj_path, ":t:r")
  local ok, lines = pcall(vim.fn.readfile, proj_path)
  if ok then
    local content = table.concat(lines, "\n")
    local rn = content:match("<RootNamespace>([^<]+)</RootNamespace>")
    if rn then root_ns = vim.trim(rn) end
  end

  local proj_dir = vim.fn.fnamemodify(proj_path, ":h")
  local file_dir = vim.fn.fnamemodify(file_path, ":h")
  local rel      = file_dir:sub(#proj_dir + 2)

  if rel == "" then return root_ns end
  return root_ns .. "." .. rel:gsub("/", ".")
end

--- Replace the namespace declaration in a file on disk.
function M.patch_file(file_path, ns)
  local ok, lines = pcall(vim.fn.readfile, file_path)
  if not ok then return end
  local changed = false
  for i, l in ipairs(lines) do
    local new = l:gsub("^(namespace%s+)([%w%.]+)", function(kw) changed = true; return kw .. ns end)
    lines[i] = new
  end
  if changed then vim.fn.writefile(lines, file_path) end
end

--- Replace the namespace declaration in the current live buffer.
function M.patch_buf(bufnr, ns)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  for i = 0, vim.api.nvim_buf_line_count(bufnr) - 1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
    local new  = line:gsub("^(namespace%s+)([%w%.]+)", "%1" .. ns)
    if new ~= line then
      vim.api.nvim_buf_set_lines(bufnr, i, i + 1, false, { new })
      return true
    end
  end
  return false
end

return M
