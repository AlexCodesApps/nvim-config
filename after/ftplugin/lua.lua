do
	local config = vim.lsp.config.luals
	if not config or not config.cmd then
		goto fin
	end
	local relbin = config.cmd[1]
	local relbase = config.cmd_cwd
	local path
	if relbase and relbin:sub(1, 1) ~= '/' then
		path = vim.fs.joinpath(relbase, relbin)
	else
		path = relbin
	end
	if vim.fn.executable(path) == 0 then
		goto fin
	end
	vim.treesitter.stop()
	::fin::
end
