-- For more information about what this code is doing, refer to the README.
--
-- For an explanation about the terminology used in code comments to describe
-- conflict markers ("snapshot", "diff section", etc.), refer to
-- https://jj-vcs.github.io/jj/latest/conflicts/#conflict-markers

local M = {}
local h = {}

-- Public functions -----------------------------------------------------------

-- Convert a file containing Jujutsu conflict markers into a two-way diff
-- conflict resolution UI. If the `show_history` argument is true, then it also
-- includes a history view that displays the two sides of the conflict and
-- their ancestor.
M.run = function(show_history, marker_length)
  local ok, jj_version = pcall(M.get_jj_version)
  if not ok then
    vim.notify(
      "jj-diffconflicts: could not get jujutsu version, assuming latest version",
      vim.log.levels.ERROR
    )
    jj_version = { math.huge, math.huge, math.huge }
  end

  if marker_length == 0 or marker_length == nil then
    marker_length = vim.g.jj_diffconflicts_marker_length
    if marker_length == "" or marker_length == nil then
      marker_length = 7
    end
  end
  local patterns = h.get_patterns(jj_version, marker_length)

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
  local ok, raw_conflicts = pcall(h.extract_conflicts, patterns, lines)
  if not ok then
    vim.notify(
      "jj-diffconflicts: extract conflicts: " .. raw_conflicts,
      vim.log.levels.ERROR
    )
    return
  end
  if vim.tbl_isempty(raw_conflicts) then
    vim.notify("jj-diffconflicts: no conflicts found in buffer", vim.log.levels.WARN)
    return
  end

  local conflicts = {}
  for _, raw_conflict in ipairs(raw_conflicts) do
    local ok, conflict = pcall(h.parse_conflict, patterns, raw_conflict)
    if not ok then
      vim.notify("jj-diffconflicts: parse conflict: " .. conflict, vim.log.levels.ERROR)
      return
    end
    table.insert(conflicts, conflict)
  end

  local show_usage_message = vim.g.jj_diffconflicts_show_usage_message
  if show_usage_message == nil then
    show_usage_message = true
  end
  h.setup_ui(conflicts, show_history, show_usage_message)
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
-- version or provided marker length.
h.get_patterns = function(jj_version, marker_length)
  vim.validate({
    marker_length = {
      marker_length,
      function(arg) return type(arg) == "number" and arg > 0 end,
      "positive number",
    },
  })

  local marker = {
    top = string.rep("<", marker_length),
    bottom = string.rep(">", marker_length),
    diff = string.rep("%", marker_length),
    diff_cont = string.rep("\\", marker_length),
    snapshot = string.rep("+", marker_length),
  }

  if vim.version.lt(jj_version, { 0, 18, 0 }) then
    -- Versions prior to v0.18.0 don't include trailing explanations
    return {
      top = "^" .. marker.top .. "$",
      bottom = "^" .. marker.bottom .. "$",
      -- We need to double `marker.diff` to escape the `%` symbols
      diff = "^" .. marker.diff .. marker.diff .. "$",
      diff_cont = "^" .. marker.diff_cont .. "$",
      snapshot = "^" .. marker.snapshot .. "$",
    }
  else
    return {
      top = "^" .. marker.top .. " .+$",
      bottom = "^" .. marker.bottom .. " .+$",
      -- We need to double `marker.diff` to escape the `%` symbols
      diff = "^" .. marker.diff .. marker.diff .. " .+$",
      diff_cont = "^" .. marker.diff_cont .. " .+$",
      snapshot = "^" .. marker.snapshot .. " .+$",
    }
  end
end

-- Extract conflict sections from the buffer.
-- Return a list of objects with the raw contents of the conflicts sections,
-- along with the line numbers corresponding to their top and bottom.
--
-- For example, given the following buffer content:
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
--   {
--     top = 2,
--     bottom = 12,
--     lines = {
--       "%%%%%%% Changes from base to side #1",
--       " apple", "-grape", "+grapefruit", " orange",
--       "+++++++ Contents of side #2",
--       "APPLE", "GRAPE", "ORANGE",
--     },
--   }
-- }
h.extract_conflicts = function(patterns, buffer_lines)
  local conflicts = {}
  local lnum = 1
  local max_lnum = #buffer_lines
  while lnum <= max_lnum do
    local line = buffer_lines[lnum]
    if string.find(line, patterns.top) then
      -- We're at the start of a conflict section, iterate through the next
      -- lines until we find the end of the conflict.
      local conflict_top = lnum
      local bottom_found = false
      lnum = lnum + 1
      while lnum <= max_lnum and not bottom_found do
        line = buffer_lines[lnum]
        if not string.find(line, patterns.bottom) then
          -- Still inside conflict, continue onwards to next line
          lnum = lnum + 1
        else
          -- We found the bottom. Extract lines between top and bottom markers
          -- (excluding them) and save them for the return value.
          bottom_found = true
          local conflict_bottom = lnum
          local conflict_lines =
            vim.list_slice(buffer_lines, conflict_top + 1, conflict_bottom - 1)

          h.validate_conflict(patterns, conflict_lines)
          table.insert(conflicts, {
            top = conflict_top,
            bottom = conflict_bottom,
            lines = conflict_lines,
          })
        end
      end
      if not bottom_found then
        h.err(
          string.format(
            "could not find bottom marker matching %q",
            buffer_lines[conflict_top]
          )
        )
      end
    end
    lnum = lnum + 1
  end
  return conflicts
end

-- Validate that the expected conflict sections are present
h.validate_conflict = function(patterns, lines)
  local num_diffs = 0
  local has_snapshot = false
  for _, l in ipairs(lines) do
    if string.find(l, patterns.diff) then
      num_diffs = num_diffs + 1
    elseif string.find(l, patterns.snapshot) then
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
end

-- Parse raw lines of conflict marker into the "left", and "right" sections
-- required to display the diff UI.
--
-- For example, given the following input:
-- {
--   top = 2,
--   bottom = 12,
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
--   top_line = 2,
--   bottom_line = 12,
-- }
h.parse_conflict = function(patterns, raw_conflict)
  local lines = raw_conflict.lines
  local raw_diff = nil
  local snapshot = nil

  local section_header = lines[1]
  if string.find(section_header, patterns.diff) then
    -- diff followed by snapshot
    local diff_start = 2
    -- Skip continuation line if present (jj v0.37.0+)
    if lines[2] and string.find(lines[2], patterns.diff_cont) then
      diff_start = 3
    end
    local i = h.find_index(patterns.snapshot, lines)
    raw_diff = vim.list_slice(lines, diff_start, i - 1)
    snapshot = vim.list_slice(lines, i + 1, #lines)
  elseif string.find(section_header, patterns.snapshot) then
    -- snapshot followed by diff
    local i = h.find_index(patterns.diff, lines)
    local diff_start = i + 1
    -- Skip continuation line if present (jj v0.37.0+)
    if lines[i + 1] and string.find(lines[i + 1], patterns.diff_cont) then
      diff_start = i + 2
    end
    snapshot = vim.list_slice(lines, 2, i - 1)
    raw_diff = vim.list_slice(lines, diff_start, #lines)
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

h.setup_ui = function(conflicts, show_history, show_usage_message)
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
  h.setup_diff_splits(conflicts)
  vim.cmd.redraw()

  -- Dispatch `JJDiffConflictsReady` event
  vim.cmd.doautocmd({ "User", "JJDiffConflictsReady" })

  -- Display usage message
  if show_usage_message then
    -- We defer printing the message by 100ms, otherwise it is cleared before
    -- the UI is fully initialized
    vim.defer_fn(
      function() vim.notify("Resolve conflicts leftward then save. Use :cq to abort.") end,
      100
    )
  end
end

-- Set up a two-way diff for conflict resolution.
--
-- Both sides have the contents of the conflicted file, except that the
-- materialized conflict (i.e. the section between conflict markers) is
-- replaced by the "new" version of the diff on the left, and the snapshot on
-- the right.
h.setup_diff_splits = function(conflicts)
  local conflicted_content = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local original_filetype = vim.bo.filetype

  -- Set up right-hand side.
  vim.cmd.vsplit({ mods = { split = "belowright" } })
  vim.cmd.enew()
  local right_side = h.get_content_for_side("right_side", conflicts, conflicted_content)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, right_side)
  vim.cmd.file("snapshot")
  vim.bo.filetype = original_filetype
  vim.api.nvim_buf_set_var(0, "jj_diffconflicts_buftype", "snapshot")
  vim.cmd([[setlocal nomodifiable readonly buftype=nofile bufhidden=delete nobuflisted]])
  vim.cmd.diffthis()

  -- Set up left-hand side
  vim.cmd.wincmd("p")
  local left_side = h.get_content_for_side("left_side", conflicts, conflicted_content)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, left_side)
  vim.api.nvim_buf_set_var(0, "jj_diffconflicts_buftype", "conflicts")
  vim.cmd.diffthis()

  -- Ensure diff highlighting is up to date
  vim.cmd.diffupdate()

  -- Put cursor at the top of the first conflict section
  vim.fn.cursor(conflicts[1].top_line, 1)
end

-- Given a side (one of "left_side" or "right_side"), the full content of the
-- conflicted buffer (as a list of lines), and a list of conflicts, return the
-- content (as a list of lines) that should be displayed for that side.
h.get_content_for_side = function(side, conflicts, conflicted_content)
  for _, conflict in ipairs(conflicts) do
    -- Pad the content of the side with null values so that it has the same
    -- number of lines as the materialized conflict with markers.
    -- This enables us to replace the conflicts in `conflicted_content` by the
    -- (shorter) "side content" without shifting the indices (and thus getting
    -- out of sync with the line numbers in `conflict.{top,bottom}_line`).
    local span = conflict.bottom_line - conflict.top_line + 1
    local content_lines = conflict[side]
    local padding_lines = vim.fn["repeat"]({ vim.NIL }, span - #content_lines)
    vim.list_extend(content_lines, padding_lines)

    -- Replace materialized conflict with the padded "side content"
    for i, line in ipairs(content_lines) do
      conflicted_content[i + conflict.top_line - 1] = line
    end
  end

  -- Filter out padding from result
  return vim.tbl_filter(function(x) return x ~= vim.NIL end, conflicted_content)
end

-- Display the merge base alongside full copies of the "left" and "right" side
-- of the conflict. This can help giving more context about the intent of the
-- changes on each side.
h.setup_history_view = function()
  local load_history_split = function(name)
    vim.cmd.buffer(name) -- open buffer whose name matches the given `name`
    vim.cmd.file(name) -- set the file name
    vim.api.nvim_buf_set_var(0, "jj_diffconflicts_buftype", "history_" .. name)
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

if vim.env.TEST ~= nil then
  -- Export internal functions when running tests
  for k, v in pairs(h) do
    M[k] = v
  end
end

return M
