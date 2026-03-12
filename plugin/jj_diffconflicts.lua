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

vim.api.nvim_create_autocmd("User", {
  pattern = "JJDiffConflictsReady",
  desc = "Display usage message when the UI is ready",
  group = vim.api.nvim_create_augroup("jj-diffconflicts", { clear = true }),
  callback = function()
    local show_usage_message = vim.g.jj_diffconflicts_show_usage_message
    if show_usage_message == nil then
      show_usage_message = true
    end
    if show_usage_message then
      vim.schedule(
        function() vim.notify("Resolve conflicts leftward then save. Use :cq to abort.") end
      )
    end
  end,
})
