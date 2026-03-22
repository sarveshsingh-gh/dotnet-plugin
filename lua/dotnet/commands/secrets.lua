-- dotnet.nvim — User Secrets (dotnet user-secrets)
local cmd    = require("dotnet.commands.init")
local runner = require("dotnet.core.runner")
local picker = require("dotnet.ui.picker")
local notify = require("dotnet.notify")

local function reg(id, def) cmd.register(id, vim.tbl_extend("force", { category = "secrets" }, def)) end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function show_float(lines, title)
  while #lines > 0 and lines[#lines] == "" do table.remove(lines) end
  if #lines == 0 then lines = { "(empty)" } end
  local buf    = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local width  = math.max(50, math.min(90, vim.o.columns - 10))
  local height = math.min(#lines + 2, 25)
  vim.api.nvim_open_win(buf, true, {
    relative  = "editor", width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal", border = "rounded",
    title = " " .. title .. " ", title_pos = "center",
  })
  vim.keymap.set("n", "q",     "<cmd>close<cr>", { buffer = buf, silent = true })
  vim.keymap.set("n", "<esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
end

local function secrets_id(proj)
  local ok, lines = pcall(vim.fn.readfile, proj)
  if not ok then return nil end
  return table.concat(lines, "\n"):match("<UserSecretsId>([^<]+)</UserSecretsId>")
end

local function secrets_json_path(id)
  if vim.fn.has("win32") == 1 then
    return vim.fn.expand("$APPDATA") .. "/Microsoft/UserSecrets/" .. id .. "/secrets.json"
  else
    return vim.fn.expand("~") .. "/.microsoft/usersecrets/" .. id .. "/secrets.json"
  end
end

local function run_list(proj, cb)
  local lines = {}
  vim.fn.jobwait({ vim.fn.jobstart(
    { "dotnet", "user-secrets", "list", "--project", proj },
    {
      stdout_buffered = true,
      stderr_buffered = true,
      on_stdout = function(_, d) vim.list_extend(lines, d) end,
      on_stderr = function(_, d) vim.list_extend(lines, d) end,
      on_exit   = function() vim.schedule(function() cb(lines) end) end,
    }
  ) }, -1)
end

-- ── Commands ──────────────────────────────────────────────────────────────────

reg("secrets.init", {
  icon = "󰌾 ",
  desc = "Secrets: Init user-secrets for project",
  run  = function()
    picker.project({}, function(proj)
      runner.bg(
        { "dotnet", "user-secrets", "init", "--project", proj },
        { label = "user-secrets init", notify_success = true,
          on_exit = function(code)
            if code == 0 then
              pcall(function() require("dotnet.ui.explorer").refresh_if_open() end)
            end
          end }
      )
    end)
  end,
})

reg("secrets.set", {
  icon = "󰏒 ",
  desc = "Secrets: Set a secret",
  run  = function()
    picker.project({}, function(proj)
      if not secrets_id(proj) then
        notify.warn("No UserSecretsId — run 'Secrets: Init' first")
        return
      end
      vim.ui.input({ prompt = "Key: " }, function(key)
        if not key or key == "" then return end
        vim.ui.input({ prompt = "Value for '" .. key .. "': " }, function(value)
          if value == nil then return end
          runner.bg(
            { "dotnet", "user-secrets", "set", key, value, "--project", proj },
            { label = "user-secrets set " .. key, notify_success = true }
          )
        end)
      end)
    end)
  end,
})

reg("secrets.list", {
  icon = "󰒕 ",
  desc = "Secrets: List all secrets",
  run  = function()
    picker.project({}, function(proj)
      run_list(proj, function(lines)
        show_float(lines, "Secrets: " .. vim.fn.fnamemodify(proj, ":t:r"))
      end)
    end)
  end,
})

reg("secrets.remove", {
  icon = "󰆓 ",
  desc = "Secrets: Remove a secret",
  run  = function()
    picker.project({}, function(proj)
      run_list(proj, function(lines)
        local keys = {}
        for _, l in ipairs(lines) do
          local k = l:match("^([^=]+)%s*=")
          if k then table.insert(keys, vim.trim(k)) end
        end
        if #keys == 0 then notify.info("No secrets found"); return end
        vim.ui.select(keys, { prompt = "Remove secret:" }, function(key)
          if not key then return end
          runner.bg(
            { "dotnet", "user-secrets", "remove", key, "--project", proj },
            { label = "user-secrets remove " .. key, notify_success = true }
          )
        end)
      end)
    end)
  end,
})

reg("secrets.clear", {
  icon = "󰃢 ",
  desc = "Secrets: Clear all secrets",
  run  = function()
    picker.project({}, function(proj)
      vim.ui.select({ "Yes, clear all", "Cancel" }, {
        prompt = "Clear ALL secrets for " .. vim.fn.fnamemodify(proj, ":t:r") .. "?",
      }, function(choice)
        if not choice or choice ~= "Yes, clear all" then return end
        runner.bg(
          { "dotnet", "user-secrets", "clear", "--project", proj },
          { label = "user-secrets clear", notify_success = true }
        )
      end)
    end)
  end,
})

reg("secrets.open", {
  icon = "󰏒 ",
  desc = "Secrets: Open secrets.json in editor",
  run  = function()
    picker.project({}, function(proj)
      local id = secrets_id(proj)
      if not id then
        notify.warn("No UserSecretsId — run 'Secrets: Init' first")
        return
      end
      local path = secrets_json_path(id)
      if vim.fn.filereadable(path) == 0 then
        -- Create it with an empty object so there is something to edit
        vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
        vim.fn.writefile({ "{}" }, path)
      end
      vim.cmd("edit " .. vim.fn.fnameescape(path))
    end)
  end,
})
