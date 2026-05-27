vim.lsp.config('*', {
	capabilities = {
		textDocument = {
			completion = {
				completionItem = {
					snippetSupport = false
				}
			}
		}
	}
})

vim.diagnostic.config { virtual_text = true }
vim.lsp.log.set_level(vim.log.levels.OFF)

vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(args)
		local client = vim.lsp.get_client_by_id(args.data.client_id)
		if client and client:supports_method("textDocument/completion") then
			vim.o.complete = 'o'
			vim.keymap.set('i', '<CR>', function()
				if vim.fn.pumvisible() == 1 then
					return '<C-e><CR>'
				end
				return '<CR>'
			end, { expr = true })
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
