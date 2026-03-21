local M = {}
local h = {}

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

  local ok, version = pcall(h.get_jj_version)
  if not ok then
    vim.health.error("Could not get Jujutsu version: " .. version)
  else
    local min_version = vim.version.parse("0.18.0")
    if vim.version.ge(version, min_version) then
      vim.health.ok(string.format("Jujutsu version: %s", version))
    else
      vim.health.error(
        string.format(
          "Jujutsu version: %s (%s or above is required)",
          version,
          min_version
        )
      )
    end
  end
end

-- Return a table representing a software version that can be used as an
-- argument to `vim.version.cmp`.
h.get_jj_version = function()
  local version_cmd = vim.system({ "jj", "--version" }):wait()
  if version_cmd.code ~= 0 then
    -- Only keep first line of error message
    error(vim.split(version_cmd.stderr, "\n")[1])
  end

  return vim.version.parse(version_cmd.stdout)
end

return M
