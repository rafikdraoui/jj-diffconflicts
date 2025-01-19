-- vim: foldmethod=marker

-- Setup {{{1
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local jj = require("jj-diffconflicts")
local child = MiniTest.new_child_neovim()

local setup_child = function()
  child.lua([[vim.opt.runtimepath:append(vim.fn.getcwd())]])
  child.lua([[jj = require("jj-diffconflicts")]])
end
local set_lines = function(lines) child.api.nvim_buf_set_lines(0, 0, -1, true, lines) end
local read_file = function(filename) return vim.iter(io.lines(filename)):totable() end

local default_patterns = jj.get_patterns(jj.get_jj_version(), 7)

local T = MiniTest.new_set({
  hooks = {
    post_once = child.stop,
  },
})

-- parse_diff {{{1
T["parse_diff"] = MiniTest.new_set()
T["parse_diff"]["parses valid diff"] = function()
  local parsed_diff = jj.parse_diff({
    " apple",
    "-grape",
    "+grapefruit",
    " orange",
  })
  eq(
    parsed_diff,
    { old = { "apple", "grape", "orange" }, new = { "apple", "grapefruit", "orange" } }
  )
end
T["parse_diff"]["raises an error on invalid diff"] = function()
  local diff = {
    " apple",
    "$grape",
    "+grapefruit",
    " orange",
  }
  local expected_err = [[unexpected diff line: "$grape"]]
  expect.error(function() jj.parse_diff(diff) end, expected_err)
end

-- parse_conflict {{{1
T["parse_conflict"] = MiniTest.new_set()
T["parse_conflict"]["handles conflict with diff before snaphsot"] = function()
  local parsed_conflict = jj.parse_conflict(default_patterns, {
    top = 2,
    bottom = 12,
    lines = {
      "%%%%%%% Changes from base to side #1",
      " apple",
      "-grape",
      "+grapefruit",
      " orange",
      "+++++++ Contents of side #2",
      "APPLE",
      "GRAPE",
      "ORANGE",
    },
  })
  eq(parsed_conflict, {
    top_line = 2,
    bottom_line = 12,
    left_side = { "apple", "grapefruit", "orange" },
    right_side = { "APPLE", "GRAPE", "ORANGE" },
  })
end
T["parse_conflict"]["handles conflict with snaphsot before diff"] = function()
  local parsed_conflict = jj.parse_conflict(default_patterns, {
    top = 2,
    bottom = 12,
    lines = {
      "+++++++ Contents of side #2",
      "APPLE",
      "GRAPE",
      "ORANGE",
      "%%%%%%% Changes from base to side #1",
      " apple",
      "-grape",
      "+grapefruit",
      " orange",
    },
  })
  eq(parsed_conflict, {
    top_line = 2,
    bottom_line = 12,
    left_side = { "apple", "grapefruit", "orange" },
    right_side = { "APPLE", "GRAPE", "ORANGE" },
  })
end
T["parse_conflict"]["raises an error on invalid conflict"] = function()
  local conflict = {
    top = 2,
    bottom = 14,
    lines = {
      "apple",
      "grapefruit",
      "orange",
      "||||||| Base",
      "apple",
      "grape",
      "orange",
      "=======",
      "APPLE",
      "GRAPE",
      "ORANGE",
    },
  }
  local expected_err = "unexpected start for conflict: apple"
  expect.error(function() jj.parse_conflict(default_patterns, conflict) end, expected_err)
end

-- extract_conflict {{{1
T["extract_conflict"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart()
      setup_child()
      child.lua("default_patterns = jj.get_patterns(jj.get_jj_version(), 7)")
    end,
  },
})
T["extract_conflict"]["handles valid conflict"] = function()
  set_lines(read_file("tests/data/fruits.txt"))
  local conflict = child.lua_get("jj.extract_conflict(default_patterns)")
  local expected = {
    top = 3,
    bottom = 13,
    lines = {
      "%%%%%%% Changes from base to side #1",
      " apple",
      "-grape",
      "+grapefruit",
      " orange",
      "+++++++ Contents of side #2",
      "APPLE",
      "GRAPE",
      "ORANGE",
    },
  }
  eq(conflict, expected)
end
T["extract_conflict"]["handles conflict numbered higher than 10"] = function()
  set_lines({
    "<<<<<<< Conflict 11 of 12",
    "%%%%%%% Changes from base to side #1",
    " apple",
    "-grape",
    "+grapefruit",
    " orange",
    "+++++++ Contents of side #2",
    "APPLE",
    "GRAPE",
    "ORANGE",
    ">>>>>>> Conflict 11 of 12 ends",
  })
  local conflict = child.lua_get("jj.extract_conflict(default_patterns)")
  local expected = {
    top = 0,
    bottom = 10,
    lines = {
      "%%%%%%% Changes from base to side #1",
      " apple",
      "-grape",
      "+grapefruit",
      " orange",
      "+++++++ Contents of side #2",
      "APPLE",
      "GRAPE",
      "ORANGE",
    },
  }
  eq(conflict, expected)
end
T["extract_conflict"]["raises an error on invalid conflict with no top"] = function()
  set_lines({
    "%%%%%%% Changes from base to side #1",
    "apple",
    "-grape",
    "+grapefruit",
    "orange",
    "+++++++ Contents of side #2",
    "APPLE",
    "GRAPE",
    "ORANGE",
    ">>>>>>> Conflict 1 of 1 ends",
  })
  expect.error(
    function() child.lua_get("jj.extract_conflict(default_patterns)") end,
    "could not find top of conflict"
  )
end
T["extract_conflict"]["raises an error on invalid conflict with no bottom"] = function()
  set_lines({
    "<<<<<<< Conflict 1 of 1",
    "%%%%%%% Changes from base to side #1",
    "apple",
    "-grape",
    "+grapefruit",
    "orange",
    "+++++++ Contents of side #2",
    "APPLE",
    "GRAPE",
    "ORANGE",
  })
  expect.error(
    function() child.lua_get("jj.extract_conflict(default_patterns)") end,
    "could not find bottom of conflict"
  )
end
T["extract_conflict"]["raises an error on invalid conflict with no snapshot"] = function()
  set_lines({
    "<<<<<<< Conflict 1 of 1",
    "%%%%%%% Changes from base to side #1",
    "apple",
    "-grape",
    "+grapefruit",
    "orange",
    ">>>>>>> Conflict 1 of 1 ends",
  })
  expect.error(
    function() child.lua_get("jj.extract_conflict(default_patterns)") end,
    "could not find snapshot section"
  )
end

-- validate_conflict {{{1
T["validate_conflict"] = MiniTest.new_set()
T["validate_conflict"]["handles valid conflict"] = function()
  local lines = read_file("tests/data/fruits.txt")
  expect.no_error(function() jj.validate_conflict(default_patterns, lines) end)
end
T["validate_conflict"]["raises an error on conflict with no diff"] = function()
  local lines = {
    "<<<<<<< Conflict 1 of 1",
    "apple",
    "grapefruit",
    "orange",
    "+++++++ Contents of side #2",
    "APPLE",
    "GRAPE",
    "ORANGE",
    ">>>>>>> Conflict 1 of 1 ends",
  }
  expect.error(
    function() jj.validate_conflict(default_patterns, lines) end,
    "could not find diff section"
  )
end
T["validate_conflict"]["raises an error on conflict with multiple diffs"] = function()
  local lines = {
    "<<<<<<< Conflict 1 of 1",
    "%%%%%%% Changes from base #1 to side #1",
    "apple",
    "-grape",
    "+grapefruit",
    "orange",
    "+++++++ Contents of side #2",
    "APPLE",
    "GRAPE",
    "ORANGE",
    "%%%%%%% Changes from base #2 to side #3",
    "apple",
    "-grape",
    "+sourgrape",
    "orange",
    ">>>>>>> Conflict 1 of 1 ends",
  }
  expect.error(
    function() jj.validate_conflict(default_patterns, lines) end,
    "conflict has 3 sides"
  )
end
T["validate_conflict"]["raises an error on invalid conflict"] = function()
  local lines = {
    "<<<<<<< Conflict 1 of 1",
    "%%%%%%% Changes from base to side #1",
    "apple",
    "-grape",
    "+grapefruit",
    "orange",
    ">>>>>>> Conflict 1 of 1 ends",
  }
  expect.error(
    function() jj.validate_conflict(default_patterns, lines) end,
    "could not find snapshot"
  )
end

return T
