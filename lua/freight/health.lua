-- Health check for :checkhealth freight.
-- Reports the process, curl availability, the binary (including whether it is
-- stale relative to the OCaml sources), and relevant configuration.

local M = {}

local health = vim.health or require("health")
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error_ = health.error or health.report_error
local info = health.info or health.report_info

function M.check()
  local freight = require("freight")

  start("freight")

  -- Process / RPC channel
  local channel = freight.channel()
  if channel and channel > 0 then
    ok("process running (channel " .. channel .. ")")
  else
    warn("process not running", { "Open a .http file or run :FreightStart" })
  end

  -- curl
  if vim.fn.executable("curl") == 1 then
    ok("curl found: " .. (vim.fn.exepath("curl")))
  else
    error_("curl not found on $PATH", { "Install curl; freight shells out to it" })
  end

  -- Binary + staleness
  local exe = freight.executable()
  if vim.fn.filereadable(exe) == 1 then
    ok("binary present: " .. exe)
    if freight.stale_binary() then
      warn("binary is older than the OCaml sources", {
        "Run `dune build` in the plugin repo,",
        "then :FreightRestart to load the new binary",
      })
    else
      ok("binary is up to date")
    end
  else
    error_("binary not found: " .. exe, {
      "Run `dune build` in the plugin repo,",
      "or set g:freight_executable to the built main.exe",
    })
  end

  -- Config
  if vim.g.freight_executable and vim.g.freight_executable ~= "" then
    info("g:freight_executable = " .. vim.g.freight_executable)
  end
end

return M
