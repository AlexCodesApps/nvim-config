vim.diagnostic.config { virtual_text = true }
vim.lsp.log.set_level(vim.log.levels.OFF)

vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(args)
		local client = vim.lsp.get_client_by_id(args.data.client_id)
		if client and client:supports_method("textDocument/completion") then
			vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
			vim.api.nvim_create_autocmd('InsertLeave', {
				buffer = 0,
				callback = vim.snippet.stop
			})
		end
	end,
})

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
vim.lsp.enable('gopls')
vim.lsp.enable('pyright')
