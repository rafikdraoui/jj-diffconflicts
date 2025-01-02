if vim.g.jj_diffconflicts_no_command == nil then
  vim.api.nvim_create_user_command("JJDiffConflicts", function(opts)
    local show_history = opts.bang
    local marker_length = opts.count
    require("jj-diffconflicts").run(show_history, marker_length)
  end, {
    desc = "Resolve Jujutsu merge conflicts",
    bang = true, -- used to enable "history" view
    count = true, -- used to supply marker length
  })
end
