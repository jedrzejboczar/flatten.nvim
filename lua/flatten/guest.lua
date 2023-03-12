local M = {}

local function send_files(host, files, stdin)
	local send_bufs =
		"return require('flatten.core').edit_files("
		.. vim.inspect(files) .. ','
		.. "'" .. vim.v.servername .. "',"
		.. "'" .. vim.fn.getcwd() .. "',"
		.. vim.inspect(stdin) ..
		")"

	if #files < 1 and #stdin < 1 then return end

	local block = vim.fn.rpcrequest(host, "nvim_exec_lua", send_bufs, {})
	if not block then
		vim.fn.chanclose(host)
		vim.cmd("qa!")
	end
	while true do
		vim.cmd("sleep 1")
	end
end

M.init = function(host_pipe)
	-- Connect to host process
	local host = vim.fn.sockconnect("pipe", host_pipe, { rpc = true })
	-- Exit on connection error
	if host == 0 then vim.cmd("qa!") end

	-- Get new files
	local files = vim.fn.argv()
	local nfiles = #files

	vim.api.nvim_create_autocmd("StdinReadPost", {
		pattern = '*',
		callback = function()
			local readlines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
			send_files(host, files, readlines)
		end
	})

	-- No arguments, user is probably opening a nested session intentionally
	-- Or only piping input from stdin
	if nfiles < 1 then return end

	send_files(host, files, {})
end

return M
