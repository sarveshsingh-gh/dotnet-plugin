# dotnet.nvim

> ⚠️ **Personal project — built for fun and for my own workflow.**

A Neovim plugin for .NET development — solution explorer, test runner, debugger, and command palette, all in one place.

Heavily inspired by [easy-dotnet.nvim](https://github.com/GustavEikaas/easy-dotnet.nvim) by [@GustavEikaas](https://github.com/GustavEikaas) — an excellent plugin that got me started. I built this as a personal learning project to tailor the workflow exactly to my needs.

---

## Features

- **Command Palette** — fuzzy-searchable list of all dotnet actions
- **Solution Explorer** — VS Code-style tree panel for your `.sln` / `.slnx`
- **Test Explorer** — tree view with inline pass/fail/skip icons
- **Run Tests** (`t`) — runs the test under your cursor, falls back to all tests
- **Debug Tests** (`dt`) — attaches netcoredbg to the vstest host, filters to test under cursor
- **Debug API** — builds, picks launch profile (http/https), sets env vars, launches under DAP
- **Background jobs** — build, run, test all run async with spinner notifications
- **DAP integration** — works with [nvim-dap](https://github.com/mfussenegger/nvim-dap) + netcoredbg

---

## Requirements

- Neovim >= 0.10
- [nvim-dap](https://github.com/mfussenegger/nvim-dap) (for debugging)
- [netcoredbg](https://github.com/Samsung/netcoredbg) installed and in PATH
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (for command palette)
- .NET SDK installed

---

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "sarveshsingh-gh/dotnet-plugin",
  name = "dotnet.nvim",
  ft   = { "cs", "fsproj", "csproj" },
  config = function()
    require("dotnet").setup({
      auto_find_sln = true,
      dap = {
        enabled           = true,
        netcoredbg_paths  = { "/usr/bin/netcoredbg" },
        adapter_name      = "coreclr",
      },
    })
  end,
}
```

---

## Configuration

```lua
require("dotnet").setup({
  auto_find_sln = true,          -- auto-detect .sln/.slnx on startup

  palette = {
    cmd   = "Dotnet",            -- :Dotnet opens the palette
    alias = "D",                 -- :D shorthand
  },

  dap = {
    enabled          = true,
    netcoredbg_paths = {
      "/usr/bin/netcoredbg",
      vim.fn.expand("~/.local/share/nvim/mason/bin/netcoredbg"),
    },
    adapter_name = "coreclr",
    console      = "integratedTerminal",
  },
})
```

---

## Usage

### Command Palette

Open with `:D` or map a key:

```lua
vim.keymap.set("n", "<leader><leader>", "<cmd>D<cr>")
```

### Buffer keymaps (auto-set on `.cs` files)

| Key  | Action |
|------|--------|
| `t`  | Run test under cursor (falls back to all tests in project) |
| `dt` | Debug test under cursor via DAP |

### Solution Explorer

```lua
-- Toggle
require("dotnet.ui.explorer").toggle()

-- Reveal current file
require("dotnet.ui.explorer").reveal()
```

### Test Explorer

```lua
require("dotnet.ui.test_explorer").toggle()
```

| Key    | Action |
|--------|--------|
| `r`    | Run test / class / project under cursor |
| `R`    | Run all tests |
| `d`    | Debug test project under cursor |
| `f`    | Run failed tests |
| `e`    | Refresh discovery |
| `<CR>` | Run / expand node |

### Debug API project

Open palette → **Debug** → select project → select launch profile (http/https) → DAP starts with your `launchSettings.json` env vars applied.

---

## How test debugging works

`dt` uses `VSTEST_HOST_DEBUG=1` — the vstest host prints its PID to stdout and waits for a debugger to attach. The plugin parses the PID, attaches netcoredbg, and after the session ends runs a TRX pass to update the gutter signs.

---

## Credits

- [easy-dotnet.nvim](https://github.com/GustavEikaas/easy-dotnet.nvim) — the original inspiration, go check it out if you want a more polished experience
- [nvim-dap](https://github.com/mfussenegger/nvim-dap) — debug adapter protocol for Neovim
- [netcoredbg](https://github.com/Samsung/netcoredbg) — .NET debugger

---

## Disclaimer

This plugin was built for **personal use** and is tailored to my own workflow. It is not meant to compete with or replace easy-dotnet.nvim. If you find it useful, great! If something breaks, PRs are welcome — but please be nice 😄
