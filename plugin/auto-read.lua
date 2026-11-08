if vim.g.loaded_auto_read then
	return
end
vim.g.loaded_auto_read = true

vim.api.nvim_create_user_command("AutoRead", function(args)
	require("auto-read").start(args.args, { from_end = args.bang })
end, { nargs = 1, bang = true, complete = "file" })

vim.api.nvim_create_user_command("AutoReadStop", function()
	require("auto-read").stop()
end, {})
