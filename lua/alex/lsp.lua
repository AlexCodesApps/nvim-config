vim.diagnostic.config { virtual_text = true }
vim.lsp.set_log_level("OFF")

vim.api.nvim_create_user_command('LspRestart', function ()
	local lsps = vim.lsp.get_clients()
	for _, lsp in ipairs(lsps) do
		local name = lsp.name
		vim.lsp.enable(name, false)
		vim.lsp.enable(name, true)
		vim.notify("Restarted client [" .. name .. "]")
	end
end, { desc = "restarts all running language servers" })

vim.lsp.enable('luals')
vim.lsp.enable('ts_ls')
vim.lsp.enable('vscode_css_lsp')
vim.lsp.enable('vscode_html_lsp')
vim.lsp.enable('clangd')
vim.lsp.enable('emmet_language_server')
vim.lsp.enable('rust-analyzer')
vim.lsp.enable('jedi_language_server')
vim.lsp.enable('gopls')
