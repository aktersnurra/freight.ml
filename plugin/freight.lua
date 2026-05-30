if vim.g.loaded_freight then
  return
end
vim.g.loaded_freight = true

local freight = require("freight")

local function call_rpc(method, args)
  freight.call_rpc(method, args)
end

vim.api.nvim_create_user_command("FreightStart", function()
  freight.start()
end, { desc = "Start the freight RPC process" })

vim.api.nvim_create_user_command("FreightOpen", function()
  call_rpc("FreightOpen")
end, { desc = "Open a Freight request scratch buffer" })

vim.api.nvim_create_user_command("FreightRun", function()
  call_rpc("FreightRun")
end, { desc = "Run the request under the cursor" })

vim.api.nvim_create_user_command("FreightRunAll", function()
  call_rpc("FreightRunAll")
end, { desc = "Run every request in the current buffer" })

vim.api.nvim_create_user_command("FreightEnv", function(opts)
  if opts.args == "" then
    freight.select_env()
  else
    freight.call_rpc("FreightEnv", opts.args)
  end
end, { nargs = "?", desc = "Show or select the active Freight environment" })

vim.api.nvim_create_user_command("FreightView", function(opts)
  call_rpc("FreightView", opts.args)
end, {
  nargs = 1,
  complete = function()
    return { "Body", "Headers", "All", "Verbose" }
  end,
  desc = "Switch the Freight response view",
})

vim.api.nvim_create_user_command("FreightViewRunAll", function(opts)
  call_rpc("FreightViewRunAll", opts.args)
end, { nargs = 1, desc = "Open a Freight run-all result" })

vim.api.nvim_create_user_command("FreightJumpRunAll", function(opts)
  call_rpc("FreightJumpRunAll", opts.args)
end, { nargs = 1, desc = "Jump to a Freight run-all source request" })

vim.api.nvim_create_user_command("FreightRunAllSummary", function()
  call_rpc("FreightRunAllSummary")
end, { desc = "Return to the latest Freight run-all summary" })

vim.api.nvim_create_user_command("FreightInspect", function()
  call_rpc("FreightInspect")
end, { desc = "Show parsed request details" })

vim.api.nvim_create_user_command("FreightHelp", function()
  call_rpc("FreightHelp")
end, { desc = "Show Freight help" })

vim.api.nvim_create_user_command("FreightHistory", function()
  call_rpc("FreightHistory")
end, { desc = "Show Freight request history" })

vim.api.nvim_create_user_command("FreightViewHistory", function(opts)
  call_rpc("FreightViewHistory", opts.args)
end, { nargs = 1, desc = "Open a Freight history entry" })

local group = vim.api.nvim_create_augroup("freight_autostart", { clear = true })

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  group = group,
  pattern = { "*.http", "*.rest" },
  callback = function() freight.ensure_started() end,
})
