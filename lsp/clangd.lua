return  {
	cmd = { 'clangd', '--background-index=false', '--header-insertion=never', '--function-arg-placeholders=-1'},
	filetypes = { 'c', 'cpp' },
	root_markers = {
		'.clangd',
		'.clang-tidy',
		'.clang-format',
		'compile_commands.json',
		'compile_flags.txt',
		'configure.ac',
		'.git',
	},
}
