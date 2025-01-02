-- For more information about what this code is doing, refer to the README.
--
-- For an explanation about the terminology used in code comments to describe
-- conflict markers ("snapshot", "diff section", etc.), refer to
-- https://jj-vcs.github.io/jj/latest/conflicts/#conflict-markers

local M = {}
local h = {}

-- This variable will contain a table with Vim and Lua regular expressions for
-- finding conflict markers. It is set dynamically through `h.set_patterns`
-- because the patterns vary based on which version of Jujutsu is used.
local PATTERNS = nil

-- Public functions -----------------------------------------------------------

-- Convert a file containing Jujutsu conflict markers into a two-way diff
-- conflict resolution UI. If the `show_history` argument is true, then it also
-- includes a history view that displays the two sides of the conflict and
-- their ancestor.
M.run = function(show_history)
  local ok, jj_version = pcall(M.get_jj_version)
  if not ok then
    vim.notify(
      "jj-diffconflicts: could not get jujutsu version, assuming latest version",
      vim.log.levels.ERROR
    )
    jj_version = { math.huge, math.huge, math.huge }
  end
  h.set_patterns(jj_version)

  local ok, raw_conflict = pcall(h.extract_conflict)
  if not ok then
    vim.notify(
      "jj-diffconflicts: extract conflict: " .. raw_conflict,
      vim.log.levels.ERROR
    )
    return
  end

  local ok, conflict = pcall(h.parse_conflict, raw_conflict)
  if not ok then
    vim.notify("jj-diffconflicts: parse conflict: " .. conflict, vim.log.levels.ERROR)
    return
  end

  h.setup_ui(conflict, show_history)
end

-- Return a table representing a software version that can be used as an
-- argument to `vim.version.cmp`.
--
-- If the `g:jj_diffconflicts_jujutsu_version` variable is set, then it will be
-- used as the version. Otherwise we run the `jj` binary to find its version.
--
-- The function is exported because it is used by the plugin health check.
M.get_jj_version = function()
  if vim.g.jj_diffconflicts_jujutsu_version ~= nil then
    -- Escape hatch if running `jj` binary is not desirable
    return vim.version.parse(vim.g.jj_diffconflicts_jujutsu_version)
  end

  local version_cmd = vim.system({ "jj", "--version" }):wait()
  if version_cmd.code ~= 0 then
    -- Only keep first line of error message
    h.err(vim.split(version_cmd.stderr, "\n")[1])
  end

  return vim.version.parse(version_cmd.stdout)
end

-- Helpers --------------------------------------------------------------------

-- Define regular expression patterns to be used to detect conflict markers. We
-- cannot just define them as constants, since they can vary based on Jujutsu's
-- version.
h.set_patterns = function(jj_version)
  local marker = {
    top = "<<<<<<<",
    bottom = ">>>>>>>",
    diff = "%%%%%%%",
    snapshot = "+++++++",
  }

  if vim.version.lt(jj_version, { 0, 18, 0 }) then
    -- Versions prior to v0.18.0 don't include trailing explanations
    PATTERNS = {
      vim = {
        top = "^" .. marker.top .. "$",
        bottom = "^" .. marker.bottom .. "$",
        diff = "^" .. marker.diff .. "$",
        snapshot = "^" .. marker.snapshot .. "$",
      },
      lua = {
        top = "^" .. marker.top .. "$",
        bottom = "^" .. marker.bottom .. "$",
        -- We need to double `marker.diff` to escape the `%` symbols
        diff = "^" .. marker.diff .. marker.diff .. "$",
        snapshot = "^" .. marker.snapshot .. "$",
      },
    }
  else
    PATTERNS = {
      vim = {
        top = "^" .. marker.top .. [[ Conflict \d of \d$]],
        bottom = "^" .. marker.bottom .. [[ Conflict \d of \d ends$]],
        diff = "^" .. marker.diff .. [[ Changes from base to side #\d\+$]],
        snapshot = "^" .. marker.snapshot .. [[ Contents of side #\d\+$]],
      },
      lua = {
        top = "^" .. marker.top .. " Conflict %d of %d$",
        bottom = "^" .. marker.bottom .. " Conflict %d of %d ends$",
        -- We need to double `marker.diff` to escape the `%` symbols
        diff = "^" .. marker.diff .. marker.diff .. " Changes from base to side #%d+$",
        snapshot = "^" .. marker.snapshot .. " Contents of side #%d+$",
      },
    }
  end
end

-- Return the raw lines in the conflict section, along with the (0-indexed)
-- line numbers corresponding to its top and bottom. For example, given the
-- following buffer content:
--
--  1| Fruits:
--  2| <<<<<<< Conflict 1 of 1
--  3| %%%%%%% Changes from base to side #1
--  4|  apple
--  5| -grape
--  6| +grapefruit
--  7|  orange
--  8| +++++++ Contents of side #2
--  9| APPLE
-- 10| GRAPE
-- 11| ORANGE
-- 12| >>>>>>> Conflict 1 of 1 ends
--
-- Then the following will be returned:
-- {
--   top = 1,
--   bottom = 11,
--   lines = {
--     "%%%%%%% Changes from base to side #1",
--     " apple", "-grape", "+grapefruit", " orange",
--     "+++++++ Contents of side #2",
--     "APPLE", "GRAPE", "ORANGE",
--   },
-- }
h.extract_conflict = function()
  -- Find top and bottom lines of conflict.
  -- We subtract 1 from the results to have them 0-indexed, which makes them
  -- easier to use with `vim.api.nvim_*` functions.
  vim.fn.cursor(1, 1)
  local top = vim.fn.search(PATTERNS.vim.top, "cW") - 1
  if top == -1 then
    h.err("could not find top of conflict")
  end
  local bottom = vim.fn.search(PATTERNS.vim.bottom, "W") - 1
  if bottom == -1 then
    h.err("could not find bottom of conflict")
  end

  -- Extract lines between top and bottom markers (excluding them).
  -- `nvim_buf_get_lines` is "zero-indexed, end exclusive".
  local lines = vim.api.nvim_buf_get_lines(0, top + 1, bottom, true)

  -- Validate that the expected conflict sections are present
  local num_diffs = 0
  local has_snapshot = false
  for _, l in ipairs(lines) do
    if string.find(l, PATTERNS.lua.diff) then
      num_diffs = num_diffs + 1
    elseif string.find(l, PATTERNS.lua.snapshot) then
      has_snapshot = true
    end
  end
  if num_diffs == 0 then
    h.err("could not find diff section of conflict")
  end
  if num_diffs > 1 then
    h.err(
      string.format("conflict has %d sides, at most 2 sides are supported", num_diffs + 1)
    )
  end
  if not has_snapshot then
    h.err("could not find snapshot section of conflict")
  end

  return {
    top = top,
    bottom = bottom,
    lines = lines,
  }
end

-- Parse raw lines of conflict marker into the "left", and "right" sections
-- required to display the diff UI.
--
-- For example, given the following input:
-- {
--   top = 1,
--   bottom = 11,
--   lines = {
--     "%%%%%%%", " apple", "-grape", "+grapefruit", " orange",
--     "+++++++", "APPLE", "GRAPE", "ORANGE",
--   },
-- }
--
-- Then the following will be returned:
-- {
--   left_side = { "apple", "grapefruit", "orange" },
--   right_side = { "APPLE", "GRAPE", "ORANGE" },
--   top_line = 1,
--   bottom_line = 11,
-- }
h.parse_conflict = function(raw_conflict)
  local lines = raw_conflict.lines
  local raw_diff = nil
  local snapshot = nil

  local section_header = lines[1]
  if string.find(section_header, PATTERNS.lua.diff) then
    -- diff followed by snapshot
    local i = h.find_index(PATTERNS.lua.snapshot, lines)
    raw_diff = vim.list_slice(lines, 2, i - 1)
    snapshot = vim.list_slice(lines, i + 1, #lines)
  elseif string.find(section_header, PATTERNS.lua.snapshot) then
    -- snapshot followed by diff
    local i = h.find_index(PATTERNS.lua.diff, lines)
    snapshot = vim.list_slice(lines, 2, i - 1)
    raw_diff = vim.list_slice(lines, i + 1, #lines)
  else
    h.err("unexpected start for conflict: " .. section_header)
  end

  local diff = h.parse_diff(raw_diff)

  return {
    left_side = diff.new,
    right_side = snapshot,
    top_line = raw_conflict.top,
    bottom_line = raw_conflict.bottom,
  }
end

h.setup_ui = function(conflict, show_history)
  if show_history then
    -- Set up history view in a separate tab
    vim.cmd.tabnew()
    xpcall(h.setup_history_view, function(err)
      vim.cmd.tabclose()
      vim.notify("jj-diffconflicts: setup history view: " .. err, vim.log.levels.ERROR)
    end)
    vim.cmd.tabnext(1)
  end

  -- Set up conflict resolution diff
  h.setup_diff_splits(conflict)

  -- Display usage message
  vim.cmd.redraw()
  vim.notify(
    "Resolve conflicts leftward then save. Use :cq to abort.",
    vim.log.levels.WARN
  )
end

-- Set up a two-way diff for conflict resolution.
--
-- Both sides have the contents of the conflicted file, except that the
-- materialized conflict (i.e. the section between conflict markers) is
-- replaced by the "new" version of the diff on the left, and the snapshot on
-- the right.
h.setup_diff_splits = function(conflict)
  local conflicted_content = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local top = conflict.top_line
  local bottom = conflict.bottom_line

  -- Set up right-hand side.
  vim.cmd.vsplit({ mods = { split = "belowright" } })
  vim.cmd.enew()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, conflicted_content)
  vim.api.nvim_buf_set_lines(0, top, bottom + 1, false, conflict.right_side)
  vim.cmd.file("snapshot")
  vim.cmd([[setlocal nomodifiable readonly buftype=nofile bufhidden=delete nobuflisted]])
  vim.cmd.diffthis()

  -- Set up left-hand side
  vim.cmd.wincmd("p")
  vim.api.nvim_buf_set_lines(0, top, bottom + 1, false, conflict.left_side)
  vim.cmd.diffthis()

  -- Ensure diff highlighting is up to date
  vim.cmd.diffupdate()

  -- Put cursor at the top of the conflict section
  vim.fn.cursor(top + 1, 1)
end

-- Display the merge base alongside full copies of the "left" and "right" side
-- of the conflict. This can help giving more context about the intent of the
-- changes on each side.
h.setup_history_view = function()
  local load_history_split = function(name)
    vim.cmd.buffer(name) -- open buffer whose name matches the given `name`
    vim.cmd.file(name) -- set the file name
    vim.cmd([[setlocal statusline=%t]]) -- only display the file name in status line
    vim.cmd([[setlocal nomodifiable readonly]])
    vim.cmd.diffthis()
  end

  -- Open three vertical splits, and put cursor in left-most one
  vim.cmd.vsplit()
  vim.cmd.vsplit()
  vim.cmd.wincmd("h")
  vim.cmd.wincmd("h")

  -- Fill left-most split with content of `$left`
  load_history_split("left")

  -- Fill middle split with content of `$base` (i.e. the original text before
  -- the two sides diverged)
  vim.cmd.wincmd("l")
  load_history_split("base")

  -- Fill right-most split with content of `$right`
  vim.cmd.wincmd("l")
  load_history_split("right")

  -- Put cursor back in middle split
  vim.cmd.wincmd("h")
end

-- Parse the diff section into the "old" and "new" versions.
h.parse_diff = function(diff)
  local old, new = {}, {}
  for _, line in ipairs(diff) do
    local symbol, rest = string.sub(line, 1, 1), string.sub(line, 2, -1)
    if symbol == "+" then
      table.insert(new, rest)
    elseif symbol == "-" then
      table.insert(old, rest)
    elseif symbol == " " then
      table.insert(old, rest)
      table.insert(new, rest)
    else
      h.err(string.format("unexpected diff line: %q", line))
    end
  end

  return { old = old, new = new }
end

-- Return the index of the first item matching `pattern` in the given list.
-- Raise an error if none can be found.
h.find_index = function(pattern, list)
  for i, x in ipairs(list) do
    if string.find(x, pattern) then
      return i
    end
  end
  h.err(string.format("could not find element matching pattern %q", pattern))
end

h.err = function(msg) error(msg, 0) end

return M
