-- dotnet.nvim — Docker commands
local cmd    = require("dotnet.commands.init")
local runner = require("dotnet.core.runner")
local picker = require("dotnet.ui.picker")

local function reg(id, def)
  cmd.register(id, vim.tbl_extend("force", { category = "docker" }, def))
end

local function notify() return require("dotnet.notify") end

local function check_docker()
  if vim.fn.executable("docker") == 0 then
    notify().error("docker not found in PATH")
    return false
  end
  return true
end

-- Walk up from dir looking for docker-compose file
local function find_compose(dir)
  local d = vim.fn.fnamemodify(dir or vim.fn.getcwd(), ":p"):gsub("/$", "")
  while d ~= "" do
    for _, name in ipairs({ "docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml" }) do
      if vim.fn.filereadable(d .. "/" .. name) == 1 then return d .. "/" .. name end
    end
    local parent = vim.fn.fnamemodify(d, ":h")
    if parent == d then break end
    d = parent
  end
end

-- Synchronously list containers; all=true includes stopped ones
local function get_containers(all)
  local args = { "docker", "ps", "--format", "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}" }
  if all then table.insert(args, 3, "-a") end
  local lines = {}
  vim.fn.jobwait({ vim.fn.jobstart(args, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      for _, l in ipairs(data) do if l ~= "" then table.insert(lines, l) end end
    end,
  }) }, 5000)
  local result = {}
  for _, l in ipairs(lines) do
    local id, name, image, status = l:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t(.+)$")
    if id then table.insert(result, { id = id, name = name, image = image, status = status }) end
  end
  return result
end

-- ── Project type detection ────────────────────────────────────────────────────

-- Returns "web" | "worker" | "func" | "console" | "test" | "library"
local function project_type(csproj_path)
  local ok, lines = pcall(vim.fn.readfile, csproj_path)
  if not ok then return "library" end
  local content = table.concat(lines, "\n")
  if content:find("IsTestProject>%s*true") then return "test" end
  if content:find('Microsoft%.NET%.Sdk%.Functions') or content:find("AzureFunctionsVersion") then return "func" end
  if content:find('Microsoft%.NET%.Sdk%.Web') then return "web" end
  if content:find('Microsoft%.NET%.Sdk%.Worker') then return "worker" end
  if content:find('<OutputType>%s*Exe%s*</OutputType>') then return "console" end
  return "library"
end

local function is_runnable(ptype) return ptype == "web" or ptype == "worker" or ptype == "func" or ptype == "console" end
local function uses_aspnet(ptype) return ptype == "web" end
local function default_port(ptype) return ptype == "web" and "8080" or (ptype == "func" and "7071" or nil) end

-- Read <TargetFramework> from csproj and return e.g. "9.0", "10.0", "8.0"
local function detect_sdk_version(csproj_path)
  local ok, lines = pcall(vim.fn.readfile, csproj_path)
  if not ok then return "9.0" end
  local content = table.concat(lines, "\n")
  local tf = content:match("<TargetFramework>net(%d+%.%d+)</TargetFramework>")
          or content:match("<TargetFrameworks>net(%d+%.%d+)[;<]")
  return tf or "9.0"
end

-- ── Scaffold Dockerfile ───────────────────────────────────────────────────────

-- Ensure a .dockerignore exists at sln_dir (safe to call multiple times)
local function ensure_dockerignore(sln_dir)
  local path = sln_dir .. "/.dockerignore"
  if vim.fn.filereadable(path) == 1 then return end
  vim.fn.writefile({
    "**/.git",
    "**/.vs",
    "**/.vscode",
    "**/bin",
    "**/obj",
    "**/*.user",
    "**/*.suo",
    "**/TestResults",
    "docker-compose*.yml",
    "Dockerfile*",
    "*.md",
  }, path)
  notify().info(".dockerignore created at " .. path)
end

-- Dockerfile lives next to .csproj; build context is the solution dir (COPY . .)
local function write_dockerfile(proj_path, sdk_ver, port, use_aspnet_img)
  local proj_dir  = vim.fn.fnamemodify(proj_path, ":h")
  local proj_name = vim.fn.fnamemodify(proj_path, ":t:r")
  local sln       = require("dotnet.core.solution").find(proj_dir)
  local sln_dir   = sln and vim.fn.fnamemodify(sln, ":h") or proj_dir
  local sln_name  = sln and vim.fn.fnamemodify(sln, ":t") or nil

  -- csproj path relative to sln dir (used inside Dockerfile for publish)
  local rel = proj_path
  if rel:sub(1, #sln_dir + 1) == sln_dir .. "/" then rel = rel:sub(#sln_dir + 2) end

  -- Restore the project (not the solution) — works for both .sln and .slnx,
  -- and dotnet restore follows project references since we COPY . . the full tree
  local restore_target = rel

  local runtime_img = use_aspnet_img
    and ("mcr.microsoft.com/dotnet/aspnet:" .. sdk_ver)
    or  ("mcr.microsoft.com/dotnet/runtime:" .. sdk_ver)

  local lines = {
    "# Build context: solution root",
    "FROM mcr.microsoft.com/dotnet/sdk:" .. sdk_ver .. " AS build",
    "WORKDIR /src",
    "COPY . .",
    'RUN dotnet restore "' .. restore_target .. '"',
    'RUN dotnet publish "' .. rel .. '" -c Release -o /app/publish --no-restore',
    "",
    "FROM " .. runtime_img .. " AS final",
    "WORKDIR /app",
  }
  if port then table.insert(lines, "EXPOSE " .. port) end
  vim.list_extend(lines, {
    "COPY --from=build /app/publish .",
    'ENTRYPOINT ["dotnet", "' .. proj_name .. '.dll"]',
    "",
  })

  ensure_dockerignore(sln_dir)
  local dockerfile = proj_dir .. "/Dockerfile"
  vim.fn.writefile(lines, dockerfile)
  notify().ok("Dockerfile → " .. dockerfile)
  vim.cmd("edit " .. vim.fn.fnameescape(dockerfile))
end

local function do_scaffold()
  picker.project({}, function(proj)
    local ptype = project_type(proj)
    if not is_runnable(ptype) then
      notify().warn(vim.fn.fnamemodify(proj, ":t:r") .. " is a " .. ptype .. " — no Dockerfile needed")
      return
    end

    local detected = detect_sdk_version(proj)
    local sdk_versions = { detected }
    for _, v in ipairs({ "10.0", "9.0", "8.0", "7.0", "6.0" }) do
      if v ~= detected then table.insert(sdk_versions, v) end
    end
    vim.ui.select(sdk_versions, { prompt = "SDK version (detected: " .. detected .. "):" }, function(sdk_ver)
      if not sdk_ver then return end

      local function write_with_port(port)
        write_dockerfile(proj, sdk_ver, port, uses_aspnet(ptype))
      end

      local dport = default_port(ptype)
      if dport then
        vim.ui.input({ prompt = "Port: ", default = dport }, function(port)
          if port and port ~= "" then write_with_port(port) end
        end)
      else
        write_with_port(nil)
      end
    end)
  end)
end

-- ── Scaffold all Dockerfiles ──────────────────────────────────────────────────

local function do_scaffold_all()
  local sln = require("dotnet.core.solution").find()
  if not sln then notify().warn("No solution found"); return end
  local sln_dir  = vim.fn.fnamemodify(sln, ":h")
  local projects = require("dotnet.core.solution").projects(sln)

  local runnable = {}
  for _, p in ipairs(projects) do
    local ptype = project_type(p)
    if is_runnable(ptype) then
      table.insert(runnable, { proj = p, ptype = ptype })
    end
  end

  if #runnable == 0 then
    notify().warn("No runnable projects found in solution")
    return
  end

  -- Use per-project SDK version so each Dockerfile matches its TargetFramework
  local created = {}
  for _, item in ipairs(runnable) do
    local sdk_ver = detect_sdk_version(item.proj)
    local port    = default_port(item.ptype)
    write_dockerfile(item.proj, sdk_ver, port, uses_aspnet(item.ptype))
    table.insert(created, vim.fn.fnamemodify(item.proj, ":t:r") .. " (" .. sdk_ver .. ")")
  end

  if #created > 0 then
    notify().ok("Dockerfiles written: " .. table.concat(created, ", "))
  end
end

-- ── Build ─────────────────────────────────────────────────────────────────────

local function do_build()
  if not check_docker() then return end
  picker.project({}, function(proj)
    local proj_dir   = vim.fn.fnamemodify(proj, ":h")
    local proj_name  = vim.fn.fnamemodify(proj, ":t:r"):lower()
    local sln        = require("dotnet.core.solution").find(proj_dir)
    local sln_dir    = sln and vim.fn.fnamemodify(sln, ":h") or proj_dir
    local dockerfile = proj_dir .. "/Dockerfile"  -- per-project Dockerfile

    if vim.fn.filereadable(dockerfile) == 0 then
      notify().warn("No Dockerfile in " .. proj_dir .. " — run Docker: Scaffold Dockerfile first")
      return
    end

    vim.ui.input({ prompt = "Image tag: ", default = proj_name .. ":latest" }, function(tag)
      if not tag or tag == "" then return end
      -- context is sln dir so COPY . . gets the whole solution
      runner.bg(
        { "docker", "build", "-t", tag, "-f", dockerfile, sln_dir },
        { cwd = sln_dir, label = "docker build " .. tag }
      )
    end)
  end)
end

-- ── Run ───────────────────────────────────────────────────────────────────────

local function do_run()
  if not check_docker() then return end
  -- List local images to pick from
  local lines = {}
  vim.fn.jobwait({ vim.fn.jobstart(
    { "docker", "images", "--format", "{{.Repository}}:{{.Tag}}" },
    { stdout_buffered = true,
      on_stdout = function(_, data)
        for _, l in ipairs(data) do if l ~= "" then table.insert(lines, l) end end
      end }
  ) }, 5000)

  if #lines == 0 then
    notify().warn("No local Docker images found — build one first")
    return
  end

  vim.ui.select(lines, { prompt = "Image to run:" }, function(image)
    if not image then return end
    vim.ui.input({ prompt = "Extra args (e.g. -p 8080:8080): ", default = "-p 8080:8080 --rm" }, function(extra)
      if extra == nil then return end
      local args = { "docker", "run" }
      for part in extra:gmatch("%S+") do table.insert(args, part) end
      table.insert(args, image)
      runner.term(args, { label = "docker run " .. image })
    end)
  end)
end

-- ── List containers (Telescope) ───────────────────────────────────────────────

local function do_ls()
  if not check_docker() then return end

  local ok_p,  pickers   = pcall(require, "telescope.pickers")
  local ok_f,  finders   = pcall(require, "telescope.finders")
  local ok_c,  conf      = pcall(require, "telescope.config")
  local ok_a,  actions   = pcall(require, "telescope.actions")
  local ok_as, act_state = pcall(require, "telescope.actions.state")
  if not (ok_p and ok_f and ok_c and ok_a and ok_as) then return end

  local containers = get_containers(true)
  if #containers == 0 then notify().info("No containers"); return end

  pickers.new({}, {
    prompt_title = "Docker Containers  <CR> logs · <C-k> kill · <C-s> shell",
    finder = finders.new_table({
      results = containers,
      entry_maker = function(c)
        local running = c.status:match("^Up") ~= nil
        local icon = running and "󰐊 " or "󰓛 "
        return {
          value   = c,
          display = string.format("%s%-20s  %-30s  %s", icon, c.name, c.image, c.status),
          ordinal = c.name .. " " .. c.image,
        }
      end,
    }),
    sorter = conf.values.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      -- CR: show logs in terminal
      actions.select_default:replace(function()
        local sel = act_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if not sel then return end
        runner.term({ "docker", "logs", "-f", sel.value.id },
          { label = "docker logs " .. sel.value.name })
      end)
      -- C-k: kill container
      local function do_kill()
        local sel = act_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if not sel then return end
        runner.bg({ "docker", "rm", "-f", sel.value.id },
          { label = "docker rm " .. sel.value.name })
      end
      map("i", "<C-k>", do_kill)
      map("n", "<C-k>", do_kill)
      -- C-s: open shell
      local function do_shell()
        local sel = act_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if not sel then return end
        runner.term({ "docker", "exec", "-it", sel.value.id, "sh" },
          { label = "shell: " .. sel.value.name })
      end
      map("i", "<C-s>", do_shell)
      map("n", "<C-s>", do_shell)
      return true
    end,
  }):find()
end

-- ── Attach debugger ───────────────────────────────────────────────────────────

local function do_attach()
  if not check_docker() then return end
  local ok, dap = pcall(require, "dap")
  if not ok then notify().error("nvim-dap is required for Docker attach"); return end

  local containers = get_containers(false)  -- running only
  local dotnet_containers = vim.tbl_filter(function(c)
    return c.status:match("^Up") ~= nil
  end, containers)

  if #dotnet_containers == 0 then
    notify().warn("No running containers found")
    return
  end

  vim.ui.select(dotnet_containers, {
    prompt      = "Attach debugger to container:",
    format_item = function(c) return c.name .. "  (" .. c.image .. ")" end,
  }, function(container)
    if not container then return end

    -- Install vsdbg in container if not already present
    notify().info("Installing vsdbg in " .. container.name .. "…")
    local install_cmd = {
      "docker", "exec", container.id, "sh", "-c",
      "[ -f /vsdbg/vsdbg ] || (apt-get update -qq && apt-get install -yqq curl unzip && " ..
      "curl -sSL https://aka.ms/getvsdbgsh | bash /dev/stdin -v latest -l /vsdbg)"
    }
    vim.fn.jobwait({ vim.fn.jobstart(install_cmd, { stdout_buffered = true }) }, 60000)

    -- Register a temporary docker pipe adapter
    local adapter_name = "coreclr-docker"
    dap.adapters[adapter_name] = {
      type = "pipe",
      pipe = { "docker", "exec", "-i", container.id, "/vsdbg/vsdbg", "--interpreter=vscode" },
    }

    -- List dotnet processes in the container
    local pid_lines = {}
    vim.fn.jobwait({ vim.fn.jobstart(
      { "docker", "exec", container.id, "sh", "-c", "ps -eo pid,comm | grep dotnet" },
      { stdout_buffered = true,
        on_stdout = function(_, data)
          for _, l in ipairs(data) do if l ~= "" then table.insert(pid_lines, l) end end
        end }
    ) }, 5000)

    local processes = {}
    for _, l in ipairs(pid_lines) do
      local pid, name = l:match("^%s*(%d+)%s+(.+)$")
      if pid then table.insert(processes, { pid = tonumber(pid), name = vim.trim(name) }) end
    end

    local function start_session(pid)
      dap.run({
        type    = adapter_name,
        request = "attach",
        processId = pid,
        justMyCode = false,
      })
    end

    if #processes == 0 then
      vim.ui.input({ prompt = "Process ID to attach: " }, function(pid_str)
        local pid = tonumber(pid_str)
        if pid then start_session(pid) end
      end)
    elseif #processes == 1 then
      start_session(processes[1].pid)
    else
      vim.ui.select(processes, {
        prompt      = "Select process:",
        format_item = function(p) return p.name .. " (pid " .. p.pid .. ")" end,
      }, function(p)
        if p then start_session(p.pid) end
      end)
    end
  end)
end

-- ── Compose helpers ───────────────────────────────────────────────────────────

local function compose_file_or_warn()
  local f = find_compose()
  if not f then notify().warn("No docker-compose.yml found (searched up from cwd)") end
  return f
end

-- ── Scaffold docker-compose.yml ──────────────────────────────────────────────

local function do_compose_scaffold()
  local sln      = require("dotnet.core.solution").find()
  local sln_dir  = sln and vim.fn.fnamemodify(sln, ":h") or vim.fn.getcwd()
  local compose_path = sln_dir .. "/docker-compose.yml"

  local function write_compose(services)
    local lines = { "services:" }
    local port_n = 8080

    for _, svc in ipairs(services) do
      local proj_dir = vim.fn.fnamemodify(svc.proj, ":h")
      -- Dockerfile path relative to sln_dir (the compose context)
      local rel_df = proj_dir
      if rel_df:sub(1, #sln_dir + 1) == sln_dir .. "/" then
        rel_df = rel_df:sub(#sln_dir + 2)
      end
      local dockerfile_rel = rel_df .. "/Dockerfile"

      vim.list_extend(lines, {
        "",
        "  " .. svc.name .. ":",
        "    build:",
        "      context: .",
        "      dockerfile: " .. dockerfile_rel,
      })

      if svc.port then
        vim.list_extend(lines, {
          "    ports:",
          '      - "' .. svc.port .. ":" .. svc.port .. '"',
          "    environment:",
          "      - ASPNETCORE_ENVIRONMENT=Development",
          "      - ASPNETCORE_URLS=http://+:" .. svc.port,
        })
      else
        vim.list_extend(lines, {
          "    environment:",
          "      - DOTNET_ENVIRONMENT=Development",
        })
      end
    end

    vim.list_extend(lines, {
      "",
      "  # Uncomment to add SQL Server:",
      "  # db:",
      "  #   image: mcr.microsoft.com/mssql/server:2022-latest",
      "  #   environment:",
      "  #     - ACCEPT_EULA=Y",
      '  #     - SA_PASSWORD=YourStrong@Passw0rd',
      "  #   ports:",
      '  #     - "1433:1433"',
      "",
    })

    vim.fn.writefile(lines, compose_path)
    notify().ok("docker-compose.yml → " .. compose_path)
    vim.cmd("edit " .. vim.fn.fnameescape(compose_path))
  end

  -- Detect runnable projects automatically
  local all_projects = sln and require("dotnet.core.solution").projects(sln) or {}
  local runnable = {}
  for _, p in ipairs(all_projects) do
    local ptype = project_type(p)
    if is_runnable(ptype) then
      table.insert(runnable, {
        proj  = p,
        ptype = ptype,
        name  = vim.fn.fnamemodify(p, ":t:r"):lower():gsub("[%.]", "-"),
        port  = default_port(ptype),
      })
    end
  end

  if #runnable == 0 then
    notify().warn("No runnable projects found in solution (web/worker/func/console only)")
    return
  end

  -- Warn about projects that need a Dockerfile scaffolded first
  local missing = {}
  for _, svc in ipairs(runnable) do
    local proj_dir = vim.fn.fnamemodify(svc.proj, ":h")
    if vim.fn.filereadable(proj_dir .. "/Dockerfile") == 0 then
      table.insert(missing, vim.fn.fnamemodify(svc.proj, ":t:r"))
    end
  end
  if #missing > 0 then
    notify().warn("Missing Dockerfile for: " .. table.concat(missing, ", ") .. " — scaffold them first")
  end

  write_compose(runnable)
end

-- ── Add DB service to compose ─────────────────────────────────────────────────

local DB_TEMPLATES = {
  {
    label = "SQL Server 2022",
    name  = "db",
    lines = function(name, pwd)
      return {
        "  " .. name .. ":",
        "    image: mcr.microsoft.com/mssql/server:2022-latest",
        "    environment:",
        "      - ACCEPT_EULA=Y",
        "      - SA_PASSWORD=" .. pwd,
        "      - MSSQL_PID=Developer",
        "    ports:",
        '      - "1433:1433"',
        "    volumes:",
        "      - " .. name .. "_data:/var/opt/mssql",
      }
    end,
    volume = true,
  },
  {
    label = "PostgreSQL 16",
    name  = "postgres",
    lines = function(name, pwd)
      return {
        "  " .. name .. ":",
        "    image: postgres:16-alpine",
        "    environment:",
        "      - POSTGRES_PASSWORD=" .. pwd,
        "      - POSTGRES_DB=appdb",
        "    ports:",
        '      - "5432:5432"',
        "    volumes:",
        "      - " .. name .. "_data:/var/lib/postgresql/data",
      }
    end,
    volume = true,
  },
  {
    label = "MySQL 8",
    name  = "mysql",
    lines = function(name, pwd)
      return {
        "  " .. name .. ":",
        "    image: mysql:8",
        "    environment:",
        "      - MYSQL_ROOT_PASSWORD=" .. pwd,
        "      - MYSQL_DATABASE=appdb",
        "    ports:",
        '      - "3306:3306"',
        "    volumes:",
        "      - " .. name .. "_data:/var/lib/mysql",
      }
    end,
    volume = true,
  },
  {
    label = "MongoDB 7",
    name  = "mongo",
    lines = function(name, pwd)
      return {
        "  " .. name .. ":",
        "    image: mongo:7",
        "    environment:",
        "      - MONGO_INITDB_ROOT_USERNAME=admin",
        "      - MONGO_INITDB_ROOT_PASSWORD=" .. pwd,
        "    ports:",
        '      - "27017:27017"',
        "    volumes:",
        "      - " .. name .. "_data:/data/db",
      }
    end,
    volume = true,
  },
  {
    label = "Redis 7",
    name  = "redis",
    lines = function(name, _)
      return {
        "  " .. name .. ":",
        "    image: redis:7-alpine",
        "    ports:",
        '      - "6379:6379"',
        "    volumes:",
        "      - " .. name .. "_data:/data",
      }
    end,
    volume = true,
  },
}

local function do_compose_add_db()
  local f = compose_file_or_warn(); if not f then return end

  vim.ui.select(DB_TEMPLATES, {
    prompt      = "Add database service:",
    format_item = function(t) return t.label end,
  }, function(tpl)
    if not tpl then return end

    vim.ui.input({ prompt = "Service name: ", default = tpl.name }, function(name)
      if not name or name == "" then return end

      local default_pwd = "YourStrong@Passw0rd"
      local pwd_prompt  = tpl.label:match("Redis") and "Password (leave blank for none): " or "Password: "
      vim.ui.input({ prompt = pwd_prompt, default = default_pwd }, function(pwd)
        if pwd == nil then return end

        local existing = vim.fn.readfile(f)

        -- Check if service name already exists
        for _, l in ipairs(existing) do
          if l:match("^  " .. vim.pesc(name) .. ":") then
            notify().warn("Service '" .. name .. "' already exists in compose file")
            return
          end
        end

        -- Find insertion point: before the last blank line / volumes section, or at end
        local insert_before = #existing + 1
        for i = #existing, 1, -1 do
          if existing[i]:match("^volumes:") then insert_before = i; break end
        end

        -- Build service block
        local svc_lines = { "" }
        vim.list_extend(svc_lines, tpl.lines(name, pwd ~= "" and pwd or ""))

        -- Insert service lines
        for j, l in ipairs(svc_lines) do
          table.insert(existing, insert_before + j - 1, l)
        end

        -- Add/update volumes section
        if tpl.volume then
          local vol_key = name .. "_data:"
          local has_volumes = false
          local has_vol_entry = false
          for _, l in ipairs(existing) do
            if l:match("^volumes:") then has_volumes = true end
            if l:match("^  " .. vim.pesc(vol_key)) then has_vol_entry = true end
          end
          if not has_volumes then
            table.insert(existing, "")
            table.insert(existing, "volumes:")
          end
          if not has_vol_entry then
            table.insert(existing, "  " .. vol_key)
          end
        end

        vim.fn.writefile(existing, f)
        notify().ok("Added '" .. name .. "' (" .. tpl.label .. ") to " .. vim.fn.fnamemodify(f, ":t"))
        vim.cmd("edit " .. vim.fn.fnameescape(f))
      end)
    end)
  end)
end

-- ── Open service in browser ───────────────────────────────────────────────────

local function open_browser(url)
  local cmd = vim.fn.has("mac") == 1 and "open"
           or vim.fn.has("win32") == 1 and "start"
           or "xdg-open"
  vim.fn.jobstart({ cmd, url }, { detach = true })
end

-- Parse compose file → list of { name, port } for services that expose ports
local function parse_compose_services(f)
  local ok, lines = pcall(vim.fn.readfile, f)
  if not ok then return {} end

  local services = {}
  local cur_name, in_ports = nil, false
  for _, l in ipairs(lines) do
    local svc = l:match("^  ([%w][%w%-_]+):%s*$")
    if svc then cur_name = svc; in_ports = false end

    if l:match("^    ports:") then in_ports = true end
    if in_ports and cur_name then
      -- match  - "HOST:CONTAINER"  or  - HOST:CONTAINER
      local host_port = l:match('"(%d+):%d+"') or l:match("'(%d+):%d+'") or l:match("-%s+(%d+):%d+")
      if host_port then
        -- avoid duplicates for same service
        local found = false
        for _, s in ipairs(services) do if s.name == cur_name then found = true; break end end
        if not found then table.insert(services, { name = cur_name, port = host_port }) end
        in_ports = false
      end
    end
    if l:match("^    %a") and not l:match("^    ports:") then in_ports = false end
  end
  return services
end

local function do_compose_open()
  local f = compose_file_or_warn(); if not f then return end
  local services = parse_compose_services(f)
  local web_svcs = vim.tbl_filter(function(s) return s.port ~= nil end, services)

  if #web_svcs == 0 then notify().warn("No services with exposed ports found"); return end

  vim.ui.select(web_svcs, {
    prompt      = "Open service:",
    format_item = function(s) return s.name .. "  (localhost:" .. s.port .. ")" end,
  }, function(svc)
    if not svc then return end
    local default_path = "/swagger"
    vim.ui.input({ prompt = "Path: ", default = default_path }, function(path)
      if path == nil then return end
      local url = "http://localhost:" .. svc.port .. path
      notify().info("Opening " .. url)
      open_browser(url)
    end)
  end)
end

-- ── Debug Dockerfile scaffold ─────────────────────────────────────────────────

local function write_dockerfile_debug(proj_path, sdk_ver, port, use_aspnet_img)
  local proj_dir  = vim.fn.fnamemodify(proj_path, ":h")
  local proj_name = vim.fn.fnamemodify(proj_path, ":t:r")
  local sln       = require("dotnet.core.solution").find(proj_dir)
  local sln_dir   = sln and vim.fn.fnamemodify(sln, ":h") or proj_dir

  local rel = proj_path
  if rel:sub(1, #sln_dir + 1) == sln_dir .. "/" then rel = rel:sub(#sln_dir + 2) end

  local restore_target = rel

  local runtime_img = use_aspnet_img
    and ("mcr.microsoft.com/dotnet/aspnet:" .. sdk_ver)
    or  ("mcr.microsoft.com/dotnet/runtime:" .. sdk_ver)

  local lines = {
    "# Debug image — NOT for production",
    "FROM mcr.microsoft.com/dotnet/sdk:" .. sdk_ver .. " AS debug",
    "WORKDIR /src",
    "COPY . .",
    'RUN dotnet restore "' .. restore_target .. '"',
    'RUN dotnet build "' .. rel .. '" -c Debug -o /app/debug --no-restore',
    "",
    "FROM " .. runtime_img,
    "WORKDIR /app",
  }
  if port then table.insert(lines, "EXPOSE " .. port) end
  vim.list_extend(lines, {
    "# Install vsdbg for DAP attach",
    "RUN apt-get update && apt-get install -y --no-install-recommends curl unzip \\",
    "    && curl -sSL https://aka.ms/getvsdbgsh | bash /dev/stdin -v latest -l /vsdbg \\",
    "    && rm -rf /var/lib/apt/lists/*",
    "COPY --from=debug /app/debug .",
    'ENTRYPOINT ["dotnet", "' .. proj_name .. '.dll"]',
    "",
  })

  local dockerfile = proj_dir .. "/Dockerfile.debug"
  vim.fn.writefile(lines, dockerfile)
  notify().ok("Dockerfile.debug → " .. dockerfile)
  notify().info("Use this in docker-compose.debug.yml with  dockerfile: .../Dockerfile.debug")
  vim.cmd("edit " .. vim.fn.fnameescape(dockerfile))
end

local function do_scaffold_debug()
  picker.project({}, function(proj)
    local ptype = project_type(proj)
    if not is_runnable(ptype) then
      notify().warn(vim.fn.fnamemodify(proj, ":t:r") .. " is a " .. ptype .. " — not runnable")
      return
    end
    local detected = detect_sdk_version(proj)
    local sdk_versions = { detected }
    for _, v in ipairs({ "10.0", "9.0", "8.0", "7.0", "6.0" }) do
      if v ~= detected then table.insert(sdk_versions, v) end
    end
    vim.ui.select(sdk_versions, { prompt = "SDK version (detected: " .. detected .. "):" }, function(sdk_ver)
      if not sdk_ver then return end
      local port = default_port(ptype)
      if port then
        vim.ui.input({ prompt = "Port: ", default = port }, function(p)
          if p and p ~= "" then write_dockerfile_debug(proj, sdk_ver, p, uses_aspnet(ptype)) end
        end)
      else
        write_dockerfile_debug(proj, sdk_ver, nil, uses_aspnet(ptype))
      end
    end)
  end)
end

-- ── Compose ───────────────────────────────────────────────────────────────────

local function do_compose_up()
  if not check_docker() then return end
  local f = compose_file_or_warn(); if not f then return end
  local cwd = vim.fn.fnamemodify(f, ":h")
  vim.ui.select(
    { "Foreground (terminal)", "Foreground + rebuild (--build)", "Detached (-d)", "Detached + rebuild (-d --build)" },
    { prompt = "docker compose up:" },
    function(choice)
      if not choice then return end
      local rebuild = choice:match("rebuild") ~= nil
      if choice:match("Detached") then
        local args = { "docker", "compose", "-f", f, "up", "-d" }
        if rebuild then table.insert(args, "--build") end
        runner.bg(args, { cwd = cwd, label = "docker compose up -d" })
      else
        local args = { "docker", "compose", "-f", f, "up" }
        if rebuild then table.insert(args, "--build") end
        runner.term(args, { cwd = cwd, label = "docker compose up" })
      end
    end)
end

local function do_compose_down()
  if not check_docker() then return end
  local f = compose_file_or_warn(); if not f then return end
  local cwd = vim.fn.fnamemodify(f, ":h")
  runner.bg({ "docker", "compose", "-f", f, "down" },
    { cwd = cwd, label = "docker compose down" })
end

local function do_compose_logs()
  if not check_docker() then return end
  local f = compose_file_or_warn(); if not f then return end
  local cwd = vim.fn.fnamemodify(f, ":h")
  runner.term({ "docker", "compose", "-f", f, "logs", "-f" },
    { cwd = cwd, label = "docker compose logs" })
end

-- ── Register ──────────────────────────────────────────────────────────────────

reg("docker.scaffold", {
  icon = "󰡨 ",
  desc = "Scaffold Dockerfile",
  run  = do_scaffold,
})
reg("docker.scaffold_all", {
  icon = "󰡨 ",
  desc = "Scaffold Dockerfiles for all runnable projects",
  run  = do_scaffold_all,
})
reg("docker.compose_scaffold", {
  icon = "󰡨 ",
  desc = "Scaffold docker-compose.yml",
  run  = do_compose_scaffold,
})
reg("docker.build", {
  icon = "󰡣 ",
  desc = "Build Docker image",
  run  = do_build,
})
reg("docker.run", {
  icon = "󰐊 ",
  desc = "Run Docker container",
  run  = do_run,
})
reg("docker.ls", {
  icon = "󰡡 ",
  desc = "List containers",
  run  = do_ls,
})
reg("docker.attach", {
  icon = "󰃤 ",
  desc = "Attach debugger to container",
  run  = do_attach,
})
reg("docker.compose_add_db", {
  icon = "󰆼 ",
  desc = "Add database to docker-compose.yml",
  run  = do_compose_add_db,
})
reg("docker.compose_open", {
  icon = "󰖟 ",
  desc = "Open service in browser",
  run  = do_compose_open,
})
reg("docker.scaffold_debug", {
  icon = "󰃤 ",
  desc = "Scaffold Dockerfile.debug (for DAP attach)",
  run  = do_scaffold_debug,
})
reg("docker.compose_up", {
  icon = "󰐗 ",
  desc = "docker compose up",
  run  = do_compose_up,
})
reg("docker.compose_down", {
  icon = "󰐙 ",
  desc = "docker compose down",
  run  = do_compose_down,
})
reg("docker.compose_logs", {
  icon = "󰋙 ",
  desc = "docker compose logs",
  run  = do_compose_logs,
})

local M = {}
M.scaffold          = do_scaffold
M.scaffold_all      = do_scaffold_all
M.compose_scaffold  = do_compose_scaffold
M.build             = do_build
M.run               = do_run
M.ls                = do_ls
M.attach            = do_attach
M.compose_open      = do_compose_open
M.scaffold_debug    = do_scaffold_debug
M.compose_add_db    = do_compose_add_db
M.compose_up        = do_compose_up
M.compose_down      = do_compose_down
M.compose_logs      = do_compose_logs
return M
