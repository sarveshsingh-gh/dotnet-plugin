-- Auto-load shim: users can call require("dotnet").setup() themselves,
-- or this file ensures the module is available without crashing on load.
if vim.g.dotnet_nvim_loaded then return end
vim.g.dotnet_nvim_loaded = true
