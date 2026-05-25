if vim.g.loaded_freight then
  return
end
vim.g.loaded_freight = true

local freight = require("freight")

vim.api.nvim_create_user_command("FreightStart", function()
  freight.start()
end, { desc = "Start the freight RPC process" })

local group = vim.api.nvim_create_augroup("freight_autostart", { clear = true })

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  group = group,
  pattern = { "*.http", "*.rest" },
  callback = function() freight.ensure_started() end,
})
