local M = {}

-- Health check for detecting potential issues with running the plugin.
-- See `:help health-dev`.
M.check = function()
  vim.health.start("jj-diffconflicts report")

  if vim.fn.has("nvim-0.10.0") == 1 then
    vim.health.ok(string.format("Neovim version: %s", vim.version()))
  else
    vim.health.error("Only Neovim 0.10+ is supported")
  end

  local ok, version = pcall(require("jj-diffconflicts").get_jj_version)
  if not ok then
    vim.health.error("Could not get Jujutsu version: " .. version)
  else
    vim.health.info(string.format("Detected Jujutsu version: %s", version))
  end

  local version_override = vim.g.jj_diffconflicts_jujutsu_version
  if version_override == nil then
    vim.health.info("g:jj_diffconflicts_jujutsu_version is unset")
  else
    local msg = string.format("g:jj_diffconflicts_jujutsu_version = %q", version_override)
    local ok = pcall(vim.version.parse, version_override)
    if ok then
      vim.health.info(msg)
    else
      vim.health.error(msg)
    end
  end
end

return M
