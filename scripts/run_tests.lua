if not vim.env.MINI_NVIM_PATH then
  vim.print("The $MINI_NVIM_PATH environment variable is unset.")
  vim.print(
    "Set it to the path of a local copy of https://github.com/echasnovski/mini.nvim/.\n"
  )
  os.exit(1)
end

-- Add plugin to 'runtimepath' to be able to use it in tests
vim.opt.runtimepath:append(vim.fn.getcwd())

-- Add 'mini.nvim' to 'runtimepath' to be able to use 'mini.test'
vim.opt.runtimepath:append(vim.env.MINI_NVIM_PATH)

-- Set up 'mini.test'
local MiniTest = require("mini.test")
MiniTest.setup()

-- Run test suite
MiniTest.run()
