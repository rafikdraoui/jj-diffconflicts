if vim.g.jj_diffconflicts_no_command == nil then
  vim.api.nvim_create_user_command("JJDiffConflicts", function(opts)
    local show_history = opts.bang
    require("jj-diffconflicts").run(show_history)
  end, {
    desc = "Resolve Jujutsu merge conflicts",
    bang = true,
  })
end
