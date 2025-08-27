return {
	'saghen/blink.cmp',
	-- optional: provides snippets for the snippet source
	dependencies = { 'rafamadriz/friendly-snippets' },
	-- use a release tag to download pre-built binaries
	version = '1.*',
	-- AND/OR build from source, requires nightly: https://rust-lang.github.io/rustup/concepts/channels.html#working-with-nightly-rust
	-- build = 'cargo build --release',
	-- If you use nix, you can build from source using latest nightly rust with:
	-- build = 'nix run .#build-plugin',

	---@module 'blink.cmp'
	---@type blink.cmp.Config
	opts = {
		-- 'default' (recommended) for mappings similar to built-in completions (C-y to accept)
		-- 'super-tab' for mappings similar to vscode (tab to accept)
		-- 'enter' for enter to accept
		-- 'none' for no mappings
		--
		-- All presets have the following mappings:
		-- C-space: Open menu or open docs if already open
		-- C-n/C-p or Up/Down: Select next/previous item
		-- C-e: Hide menu
		-- C-k: Toggle signature help (if signature.enabled = true)
		--
		-- See :h blink-cmp-config-keymap for defining your own keymap
		keymap = {
			['<C-]>'] = { 'select_next', 'snippet_forward', 'fallback' },
			['<C-\\>'] = { 'select_prev', 'snippet_backward', 'fallback' },
			['<C-c>'] = { 'cancel', 'fallback' },
			['<C-p>'] = { 'accept', 'fallback' },
			['<C-Space>'] = { 'show', 'show_documentation', 'hide_documentation' },
			['<C-k>'] = { 'show_signature', 'hide_signature', 'fallback' },
		},

		appearance = {
			-- 'mono' (default) for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
			-- Adjusts spacing to ensure icons are aligned
			nerd_font_variant = 'mono'
		},

		-- (Default) Only show the documentation popup when manually triggered
		completion = { documentation = { auto_show = false } },

		-- Default list of enabled providers defined so that you can extend it
		-- elsewhere in your config, without redefining it, due to `opts_extend`
		sources = {
			default = { 'lsp', 'path', 'snippets', 'buffer' },
		},

		-- (Default) Rust fuzzy matcher for typo resistance and significantly better performance
		-- You may use a lua implementation instead by using `implementation = "lua"` or fallback to the lua implementation,
		-- when the Rust fuzzy matcher is not available, by using `implementation = "prefer_rust"`
		--
		-- See the fuzzy documentation for more information
		fuzzy = {
			implementation = "rust",
			sorts = {
				function(a, b)
					local field = vim.lsp.protocol.CompletionItemKind.Field
					if a.kind == b.kind then
						return
					end
					if a.kind == field then
						return true
					end
					if b.kind == field then
						return false
					end
				end,
				'score',
				'sort_text',
			},
		}
	},
	snippets = {
		should_show_items = function(ctx)
			return ctx.trigger.initial_kind ~= 'trigger_character' and not require('blink.cmp').snippet_active()
		end,
	},
	opts_extend = { "sources.default" },
}
