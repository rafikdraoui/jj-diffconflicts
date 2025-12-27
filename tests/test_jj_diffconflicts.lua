local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

local setup_child = function()
  child.lua([[vim.opt.runtimepath:append(vim.fn.getcwd())]])
  child.lua([[jj = require("jj-diffconflicts")]])

  -- Track how many times JJDiffConflictsReady User event is triggered
  child.lua([[
    _G.event_count = 0
    local callback = function() _G.event_count = _G.event_count + 1 end
    vim.api.nvim_create_autocmd('User', { pattern = 'JJDiffConflictsReady', callback = callback})
  ]])
end
local set_lines = function(lines) child.api.nvim_buf_set_lines(0, 0, -1, true, lines) end
local read_file = function(filename) return vim.iter(io.lines(filename)):totable() end

local SCREENSHOT = {
  fruits = "tests/screenshots/fruits_ui",
  long_markers = "tests/screenshots/long_markers_ui",
  multiple_conflicts = "tests/screenshots/multiple_conflicts_ui",
  missing_newline = "tests/screenshots/missing_newline_ui",
  no_usage_message = "tests/screenshots/no_usage_message",
}

local T = MiniTest.new_set({
  hooks = {
    post_once = child.stop,
  },
})

T["run"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart()
      setup_child()
    end,
  },
})
T["run"]["displays UI"] = function()
  set_lines(read_file("tests/data/fruits.txt"))
  child.lua("jj.run(false, 7)")

  expect.reference_screenshot(child.get_screenshot(), SCREENSHOT.fruits)

  -- Check that the JJDiffConflictsReady event was triggered once
  eq(child.lua_get("_G.event_count"), 1)

  -- Check that the current buffer is the "conflicts" buffer
  eq(child.lua_get("vim.b.jj_diffconflicts_buftype"), "conflicts")
end
T["run"]["displays an error when no valid conflict"] = function()
  set_lines({ "hello world" })
  child.lua("jj.run(false, 7)")
  expect.reference_screenshot(child.get_screenshot())
  eq(child.lua_get("_G.event_count"), 0)
end
T["run"]["handles conflicts with different marker length"] = function()
  set_lines(read_file("tests/data/long_markers.txt"))
  child.lua("jj.run(false, 15)")
  expect.reference_screenshot(child.get_screenshot(), SCREENSHOT.long_markers)
  eq(child.lua_get("_G.event_count"), 1)
end
T["run"]["does not work with wrong marker length"] = function()
  set_lines(read_file("tests/data/long_markers.txt"))
  child.lua("jj.run(false, 7)")
  expect.reference_screenshot(child.get_screenshot())
  eq(child.lua_get("_G.event_count"), 0)
end
T["run"]["uses g:jj_diffconflicts_marker_length"] = function()
  set_lines(read_file("tests/data/long_markers.txt"))
  child.g.jj_diffconflicts_marker_length = 15
  child.lua("jj.run(false, nil)")
  expect.reference_screenshot(child.get_screenshot(), SCREENSHOT.long_markers)
  eq(child.lua_get("_G.event_count"), 1)
end
T["run"]["defaults to marker length of 7"] = function()
  set_lines(read_file("tests/data/fruits.txt"))
  eq(child.lua_get("vim.g.jj_diffconflicts_marker_length"), vim.NIL)
  child.lua("jj.run(false, nil)")
  expect.reference_screenshot(child.get_screenshot(), SCREENSHOT.fruits)
  eq(child.lua_get("_G.event_count"), 1)
end
T["run"]["raises error for invalid marker length"] = function()
  set_lines(read_file("tests/data/fruits.txt"))
  expect.error(
    function() child.lua("jj.run(false, 'hello')") end,
    "marker_length: expected positive number"
  )
  eq(child.lua_get("_G.event_count"), 0)
end
T["run"]["handles multiple conflicts"] = function()
  set_lines(read_file("tests/data/multiple_conflicts.txt"))
  child.o.lines = 36
  child.lua("jj.run(false, 7)")
  expect.reference_screenshot(child.get_screenshot(), SCREENSHOT.multiple_conflicts)
  eq(child.lua_get("_G.event_count"), 1)
end
T["run"]["handles missing newlines conflicts"] = function()
  set_lines(read_file("tests/data/missing_newline_markers.txt"))
  child.lua("jj.run(false, 7)")
  expect.reference_screenshot(child.get_screenshot(), SCREENSHOT.missing_newline)
  eq(child.lua_get("_G.event_count"), 1)
end
T["run"]["hides usage message when g:jj_diffconflicts_show_usage_message is false"] = function()
  set_lines(read_file("tests/data/fruits.txt"))
  child.g.jj_diffconflicts_show_usage_message = false
  child.lua("jj.run(false, 7)")
  expect.reference_screenshot(child.get_screenshot(), SCREENSHOT.no_usage_message)
  eq(child.lua_get("_G.event_count"), 1)
end

T["history view"] = MiniTest.new_set()
T["history view"]["displays UI"] = function()
  child.restart({
    "tests/data/fruits.txt",
    "tests/data/base",
    "tests/data/left",
    "tests/data/right",
  })
  setup_child()

  child.lua("jj.run(true, 7)")
  eq(child.lua_get("_G.event_count"), 1)
  eq(child.lua_get("vim.b.jj_diffconflicts_buftype"), "conflicts")

  child.cmd("tabnext")
  expect.reference_screenshot(child.get_screenshot())
  eq(child.lua_get("vim.b.jj_diffconflicts_buftype"), "history_base")
end

return T
