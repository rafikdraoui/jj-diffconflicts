-- vim: foldmethod=marker

-- Setup {{{1
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local jj = require("jj-diffconflicts")

local read_file = function(filename) return vim.iter(io.lines(filename)):totable() end

local default_patterns = jj.get_patterns(jj.get_jj_version(), 7)

local T = MiniTest.new_set()

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

-- extract_conflicts {{{1
T["extract_conflicts"] = MiniTest.new_set()
T["extract_conflicts"]["handles single conflict"] = function()
  local lines = read_file("tests/data/fruits.txt")
  local conflict = jj.extract_conflicts(default_patterns, lines)
  local expected = {
    {
      top = 4,
      bottom = 14,
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
    },
  }
  eq(conflict, expected)
end
T["extract_conflicts"]["handles multiple conflicts"] = function()
  local lines = read_file("tests/data/multiple_conflicts.txt")
  local conflict = jj.extract_conflicts(default_patterns, lines)
  local expected = {
    {
      top = 4,
      bottom = 14,
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
    },
    {
      top = 20,
      bottom = 30,
      lines = {
        "%%%%%%% Changes from base to side #1",
        " apple",
        " grape",
        "-orange",
        "+blood orange",
        "+++++++ Contents of side #2",
        "APPLE",
        "GRAPE",
        "ORANGE",
      },
    },
  }
  eq(conflict, expected)
end
T["extract_conflicts"]["handles conflict numbered higher than 10"] = function()
  local lines = {
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
  }
  local conflict = jj.extract_conflicts(default_patterns, lines)
  local expected = {
    {
      top = 1,
      bottom = 11,
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
    },
  }
  eq(conflict, expected)
end
T["extract_conflicts"]["handles invalid conflict with no top"] = function()
  local lines = {
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
  }
  eq(jj.extract_conflicts(default_patterns, lines), {})
end
T["extract_conflicts"]["raises an error on invalid conflict with no bottom"] = function()
  local lines = {
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
  }
  expect.error(
    function() jj.extract_conflicts(default_patterns, lines) end,
    "could not find bottom marker"
  )
end
T["extract_conflicts"]["raises an error on invalid conflict with no snapshot"] = function()
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
    function() jj.extract_conflicts(default_patterns, lines) end,
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
