-- dotnet.nvim — entry point
-- require("dotnet").setup(opts)
local M = {}

local _cfg     = nil
local _sln     = nil   -- cached solution path found at startup

function M.setup(user_opts)
  _cfg = require("dotnet.config").resolve(user_opts)

  -- Load all command modules (they self-register into commands.init)
  require("dotnet.commands.build")
  require("dotnet.commands.run")
  require("dotnet.commands.test")
  require("dotnet.commands.solution")
  require("dotnet.commands.file")
  require("dotnet.commands.nuget")

  -- Register jobs + files commands in palette
  local cmd = require("dotnet.commands.init")
  cmd.register("jobs.list", {
    category = "run",
    icon     = "󰒖 ",
    desc     = "List running processes",
    run      = function() require("dotnet.telescope.jobs").open() end,
  })
  cmd.register("files.find", {
    category = "file",
    icon     = "󰱼 ",
    desc     = "Find file in solution",
    run      = function() require("dotnet.telescope.files").open() end,
  })
  cmd.register("explorer.toggle", {
    category = "file",
    icon     = "󰙅 ",
    desc     = "Toggle Solution Explorer",
    run      = function() require("dotnet.ui.explorer").toggle() end,
  })
  cmd.register("explorer.reveal", {
    category = "file",
    icon     = "󰙅 ",
    desc     = "Reveal current file in Explorer",
    run      = function() require("dotnet.ui.explorer").reveal() end,
  })
  cmd.register("test_explorer.toggle", {
    category = "test",
    icon     = "󰙨 ",
    desc     = "Toggle Test Explorer",
    run      = function() require("dotnet.ui.test_explorer").toggle() end,
  })

  -- DAP setup
  require("dotnet.dap.init").setup(_cfg.dap)

  -- Keymaps + annotate palette entries with their bindings
  require("dotnet.keymaps").setup(_cfg.keymaps)
  require("dotnet.commands.init").annotate_keys(_cfg.keymaps)

  -- :Dotnet and :D commands
  local palette_cmd = (_cfg.palette or {}).cmd or "Dotnet"
  local palette_alias = (_cfg.palette or {}).alias or "D"
  vim.api.nvim_create_user_command(palette_cmd, function()
    require("dotnet.ui.palette").open()
  end, { desc = "Dotnet command palette" })
  pcall(vim.api.nvim_create_user_command, palette_alias, function()
    require("dotnet.ui.palette").open()
  end, { desc = "Dotnet command palette" })

  -- Buffer keymaps for .cs files: t = run tests, dt = debug tests
  vim.api.nvim_create_autocmd("FileType", {
    pattern  = "cs",
    callback = function(ev)
      local function proj_for_buf()
        local file = vim.api.nvim_buf_get_name(ev.buf)
        if not _sln or file == "" then return nil end
        for _, p in ipairs(require("dotnet.core.solution").projects(_sln)) do
          local dir = vim.fn.fnamemodify(p, ":h") .. "/"
          if file:sub(1, #dir) == dir then return p end
        end
      end

      -- t: run tests for the project that owns this file
      vim.keymap.set("n", "t", function()
        local proj = proj_for_buf()
        if not proj then require("dotnet.notify").warn("Not in a dotnet project"); return end
        local signs = require("dotnet.ui.test_signs")
        signs.mark_running(proj)
        local results_dir = vim.fn.tempname()
        vim.fn.mkdir(results_dir, "p")
        local runner = require("dotnet.core.runner")
        local notify = require("dotnet.notify")
        local spin   = notify.start_spinner("Test " .. vim.fn.fnamemodify(proj, ":t"))
        vim.fn.jobstart({ "dotnet", "test", "--nologo", "--logger", "trx",
                          "--results-directory", results_dir, proj }, {
          cwd     = vim.fn.fnamemodify(proj, ":h"),
          on_exit = function(_, code)
            vim.schedule(function()
              notify.stop_spinner(spin)
              -- parse TRX
              local trx_files = vim.fn.glob(results_dir .. "/*.trx", false, true)
              local results = {}
              if trx_files and #trx_files > 0 then
                local ok, lines = pcall(vim.fn.readfile, trx_files[1])
                vim.fn.delete(results_dir, "rf")
                if ok then
                  local id_to_fqn = {}
                  local cur_id = nil
                  for _, l in ipairs(lines) do
                    local id = l:match('<UnitTest[^>]+%sid="([^"]+)"')
                    if id then cur_id = id end
                    if cur_id then
                      local cls  = l:match('className="([^"]+)"')
                      local meth = l:match('<TestMethod[^>]+%sname="([^"]+)"')
                      if cls and meth then id_to_fqn[cur_id] = cls .. "." .. meth; cur_id = nil end
                    end
                  end
                  for _, l in ipairs(lines) do
                    if l:find("UnitTestResult") and l:find('testId=') and l:find('outcome=') then
                      local tid = l:match('testId="([^"]+)"')
                      local out = l:match('outcome="([^"]+)"')
                      if tid and out and id_to_fqn[tid] then
                        local st = out:lower()
                        results[id_to_fqn[tid]] = st == "notexecuted" and "skipped" or st
                      end
                    end
                  end
                end
              else
                vim.fn.delete(results_dir, "rf")
              end
              signs.annotate(results)
              local total, passed, failed = 0, 0, 0
              for _, st in pairs(results) do
                total = total + 1
                if st == "passed" then passed = passed + 1
                elseif st == "failed" then failed = failed + 1 end
              end
              if total > 0 then
                if failed > 0 then notify.fail("Tests: " .. failed .. " failed, " .. passed .. "/" .. total .. " passed")
                else notify.ok("Tests: all " .. total .. " passed") end
              elseif code ~= 0 then notify.fail("Test build failed — press gx to see log")
              else notify.ok("Tests complete") end
            end)
          end,
        })
      end, { buffer = ev.buf, desc = "Run test project" })

      -- dt: debug tests via DAP (VSTEST_HOST_DEBUG=1 attach approach)
      vim.keymap.set("n", "dt", function()
        local ok2, err = pcall(function()
          local proj = proj_for_buf()
          if not proj then require("dotnet.notify").warn("Not in a dotnet project"); return end
          local ok, dap = pcall(require, "dap")
          if not ok then require("dotnet.notify").warn("nvim-dap not available"); return end
          local proj_dir = vim.fn.fnamemodify(proj, ":h")
          local name     = vim.fn.fnamemodify(proj, ":t:r")
          -- Start dotnet test with VSTEST_HOST_DEBUG=1 — vstest host prints its PID
          -- and waits for a debugger to attach, then continues running tests.
          local notify = require("dotnet.notify")
          local spin   = notify.start_spinner("Waiting for test host…")
          local attached = false
          vim.fn.jobstart({ "dotnet", "test", proj, "--no-build" }, {
            cwd = proj_dir,
            env = vim.tbl_extend("force", vim.fn.environ(), { VSTEST_HOST_DEBUG = "1" }),
            stdout_buffered = false,
            stderr_buffered = false,
            on_stdout = function(_, data)
              for _, line in ipairs(data or {}) do
                local pid = line:match("[Pp]rocess[Ii][Dd]%s*:%s*(%d+)")
                         or line:match("[Pp]rocess[%s_][Ii][Dd][%s:=]+(%d+)")
                         or line:match("PID[%s:=]+(%d+)")
                if pid and not attached then
                  attached = true
                  vim.schedule(function()
                    notify.stop_spinner(spin)
                    -- After debug session ends, run TRX test pass for visual ticks
                    local trx_key = "dt_trx_" .. tostring(ev.buf)
                    dap.listeners.before["event_terminated"][trx_key] = function()
                      dap.listeners.before["event_terminated"][trx_key] = nil
                      vim.schedule(function()
                        local results_dir = vim.fn.tempname()
                        vim.fn.mkdir(results_dir, "p")
                        local signs = require("dotnet.ui.test_signs")
                        signs.mark_running(proj)
                        vim.fn.jobstart({ "dotnet", "test", "--nologo", "--no-build",
                                          "--logger", "trx", "--results-directory", results_dir, proj }, {
                          cwd = proj_dir,
                          on_exit = function(_, _code)
                            vim.schedule(function()
                              local trx = vim.fn.glob(results_dir .. "/*.trx", false, true)
                              local results = {}
                              if trx and #trx > 0 then
                                local ok3, lines = pcall(vim.fn.readfile, trx[1])
                                vim.fn.delete(results_dir, "rf")
                                if ok3 then
                                  local id_to_fqn = {}
                                  local cur_id = nil
                                  for _, l in ipairs(lines) do
                                    local id = l:match('<UnitTest[^>]+%sid="([^"]+)"')
                                    if id then cur_id = id end
                                    if cur_id then
                                      local cls  = l:match('className="([^"]+)"')
                                      local meth = l:match('<TestMethod[^>]+%sname="([^"]+)"')
                                      if cls and meth then id_to_fqn[cur_id] = cls .. "." .. meth; cur_id = nil end
                                    end
                                  end
                                  for _, l in ipairs(lines) do
                                    if l:find("UnitTestResult") and l:find('testId=') and l:find('outcome=') then
                                      local tid = l:match('testId="([^"]+)"')
                                      local out = l:match('outcome="([^"]+)"')
                                      if tid and out and id_to_fqn[tid] then
                                        local st = out:lower()
                                        results[id_to_fqn[tid]] = st == "notexecuted" and "skipped" or st
                                      end
                                    end
                                  end
                                end
                              else
                                vim.fn.delete(results_dir, "rf")
                              end
                              signs.annotate(results)
                            end)
                          end,
                        })
                      end)
                    end
                    dap.run({
                      type      = "coreclr",
                      name      = "Debug Tests: " .. name,
                      request   = "attach",
                      processId = tonumber(pid),
                    })
                  end)
                end
              end
            end,
            on_exit = function(_, _code)
              vim.schedule(function()
                notify.stop_spinner(spin)
                if not attached then
                  notify.warn("Test host did not print a PID — try building first with 't'")
                end
              end)
            end,
          })
        end)
        if not ok2 then require("dotnet.notify").error("dt: " .. tostring(err)) end
      end, { buffer = ev.buf, desc = "Debug test project" })
    end,
  })

  -- Auto-find solution
  if _cfg.auto_find_sln then
    vim.schedule(function()
      local sln = require("dotnet.core.solution").find()
      if sln then
        _sln = sln
        require("dotnet.ui.explorer").set_sln(sln)
        require("dotnet.ui.test_explorer").set_sln(sln)
        require("dotnet.notify").info("Solution: " .. vim.fn.fnamemodify(sln, ":t"))
      end
    end)
  end
end

--- Access resolved config from anywhere.
function M.config() return _cfg end

--- Return the cached solution path (set at startup).
function M.sln() return _sln end

return M
