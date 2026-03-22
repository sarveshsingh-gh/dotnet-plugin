-- dotnet.nvim — Dev certificates (dotnet dev-certs https)
local cmd    = require("dotnet.commands.init")
local runner = require("dotnet.core.runner")
local notify = require("dotnet.notify")

local function reg(id, def) cmd.register(id, vim.tbl_extend("force", { category = "devcerts" }, def)) end

local function show_float(lines, title)
  while #lines > 0 and lines[#lines] == "" do table.remove(lines) end
  if #lines == 0 then lines = { "(no output)" } end
  local buf    = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local width  = math.max(50, math.min(80, vim.o.columns - 10))
  local height = math.min(#lines + 2, 15)
  vim.api.nvim_open_win(buf, true, {
    relative = "editor", width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal", border = "rounded",
    title = " " .. title .. " ", title_pos = "center",
  })
  vim.keymap.set("n", "q",     "<cmd>close<cr>", { buffer = buf, silent = true })
  vim.keymap.set("n", "<esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
end

reg("devcerts.check", {
  icon = "󰄭 ",
  desc = "Dev Certs: Check HTTPS certificate status",
  run  = function()
    local lines = {}
    vim.fn.jobwait({ vim.fn.jobstart(
      { "dotnet", "dev-certs", "https", "--check", "--verbose" },
      {
        stdout_buffered = true,
        stderr_buffered = true,
        on_stdout = function(_, d) vim.list_extend(lines, d) end,
        on_stderr = function(_, d) vim.list_extend(lines, d) end,
        on_exit   = function() vim.schedule(function() show_float(lines, "Dev Certs Status") end) end,
      }
    ) }, -1)
  end,
})

reg("devcerts.trust", {
  icon = "󰄬 ",
  desc = "Dev Certs: Trust HTTPS certificate",
  run  = function()
    runner.bg(
      { "dotnet", "dev-certs", "https", "--trust" },
      { label = "dev-certs trust", notify_success = true }
    )
  end,
})

reg("devcerts.clean", {
  icon = "󰃢 ",
  desc = "Dev Certs: Remove HTTPS dev certificates",
  run  = function()
    vim.ui.select({ "Yes, remove certificates", "Cancel" }, {
      prompt = "Remove all ASP.NET Core HTTPS dev certificates?",
    }, function(choice)
      if not choice or choice ~= "Yes, remove certificates" then return end
      runner.bg(
        { "dotnet", "dev-certs", "https", "--clean" },
        { label = "dev-certs clean", notify_success = true }
      )
    end)
  end,
})

reg("devcerts.export", {
  icon = "󰕒 ",
  desc = "Dev Certs: Export HTTPS certificate",
  run  = function()
    local default = vim.fn.getcwd() .. "/localhost.pfx"
    vim.ui.input({ prompt = "Export path (.pfx or .pem): ", default = default }, function(path)
      if not path or path == "" then return end
      local args = { "dotnet", "dev-certs", "https", "--export-path", path }
      if path:match("%.pem$") then vim.list_extend(args, { "--format", "Pem" }) end
      runner.bg(args, {
        label = "dev-certs export",
        notify_success = true,
        on_exit = function(code)
          if code == 0 then notify.ok("Exported → " .. path) end
        end,
      })
    end)
  end,
})
