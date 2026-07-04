do
	local function enable_snippets(enable)
		return {
			capabilities = {
				textDocument = {
					completion = {
						completionItem = {
							snippetSupport = enable
						}
					}
				}
			}
		}
	end
	vim.lsp.config('*', enable_snippets(false))
	local enable = enable_snippets(true)
	vim.lsp.config('ts_ls', enable)
	vim.lsp.config('cssls', enable)
	vim.lsp.config('html', enable)
	vim.lsp.config('emmet_language_server', enable)
end

vim.diagnostic.config { virtual_text = true }
vim.lsp.log.set_level(vim.log.levels.OFF)

local seen_clients = {}

vim.api.nvim_create_autocmd('LspAttach', {
	callback = function(args)
		local client = vim.lsp.get_client_by_id(args.data.client_id)
		assert (client)
		if not seen_clients[client.id] then
			vim.notify('LspAttach ' .. client.name)
			seen_clients[client.id] = true
		end
		if client and client:supports_method('textDocument/completion') then
			vim.o.complete = 'o'
			vim.keymap.set('i', '<CR>', function()
				if vim.fn.pumvisible() == 1 then
					return '<C-e><CR>'
				end
				return '<CR>'
			end, { expr = true, buf = args.buf })
		end
		if vim.bo.filetype == 'html'
			and client:supports_method('textDocument/linkedEditingRange', 0) then
			vim.lsp.linked_editing_range.enable(true, {
				client_id = client.id
			})
		end
	end,
})

vim.api.nvim_create_autocmd('LspProgress', {
	callback = function(ev)
		local value = ev.data.params.value
		vim.api.nvim_echo({ { value.message or 'done' } }, false, {
			id = 'lsp.' .. ev.data.params.token,
			kind = 'progress',
			source = 'vim.lsp',
			title = value.title,
			status = value.kind ~= 'end' and 'running' or 'success',
			percent = value.percentage,
		})
	end,
})

vim.lsp.config('gopls', {
	settings = {
		gopls = {
			semanticTokens = false
		}
	}
})

vim.lsp.enable('luals')
vim.lsp.enable('ts_ls')
vim.lsp.enable('cssls')
vim.lsp.enable('html')
vim.lsp.enable('clangd')
vim.lsp.enable('emmet_language_server')
vim.lsp.enable('rust-analyzer')
vim.lsp.enable('gopls')
vim.lsp.enable('pyright')
