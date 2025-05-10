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

  local marker_style_cmd =
    vim.system({ "jj", "config", "get", "ui.conflict-marker-style" }):wait()
  if marker_style_cmd.code ~= 0 then
    vim.health.error(
      "Could not get conflict-marker-style config: " .. marker_style_cmd.stderr
    )
  else
    local marker_style = vim.trim(marker_style_cmd.stdout)
    if marker_style ~= "diff" then
      vim.health.error("Unsupported ui.conflict-marker-style: " .. marker_style)
    else
      vim.health.ok("ui.conflict-marker-style: " .. marker_style)
    end
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
