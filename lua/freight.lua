local M = {}

local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local job_id = 0
local ready = false

local function resolve_executable()
  local g_exe = vim.g.freight_executable
  if g_exe and g_exe ~= "" then
    return g_exe
  end
  return plugin_root .. "/_build/default/bin/main.exe"
end

local function on_stderr(_, data, _)
  vim.notify("freight stderr: " .. table.concat(data, "\n"), vim.log.levels.ERROR)
end

function M.start()
  if job_id > 0 then
    vim.notify("freight: already running (channel " .. job_id .. ")")
    return
  end
  local exe = resolve_executable()
  if vim.fn.filereadable(exe) == 0 then
    vim.notify(
      "freight: executable not found at " .. exe .. ". Run `dune build` in the plugin repo or set g:freight_executable.",
      vim.log.levels.ERROR
    )
    return
  end
  job_id = vim.fn.jobstart({ exe }, { rpc = true, on_stderr = on_stderr })
  if job_id <= 0 then
    vim.notify("freight: jobstart failed (" .. job_id .. ")", vim.log.levels.ERROR)
    job_id = 0
  end
end

function M.ensure_started()
  if job_id <= 0 then
    M.start()
  end
end

function M.channel()
  return job_id
end

function M.ready()
  return ready
end

return M
