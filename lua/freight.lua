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

-- Newest mtime among the OCaml sources under the plugin root, or 0 if none
-- (e.g. an installed build with no sources shipped).
function M.newest_source_mtime()
  local newest = 0
  for _, dir in ipairs({ "lib", "bin" }) do
    for _, path in ipairs(vim.fn.glob(plugin_root .. "/" .. dir .. "/*.ml", false, true)) do
      local m = vim.fn.getftime(path)
      if m > newest then
        newest = m
      end
    end
  end
  return newest
end

-- True when a built binary exists but is older than the sources — the "pulled
-- source but forgot to rebuild" state that silently serves an old binary.
function M.stale_binary()
  local exe = resolve_executable()
  if vim.fn.filereadable(exe) == 0 then
    return false
  end
  local src = M.newest_source_mtime()
  return src > 0 and src > vim.fn.getftime(exe)
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
  if M.stale_binary() then
    vim.notify(
      "freight: binary is older than the sources — run `dune build` and :FreightRestart",
      vim.log.levels.WARN
    )
  end
  job_id = vim.fn.jobstart({ exe }, { rpc = true, on_stderr = on_stderr })
  if job_id <= 0 then
    vim.notify("freight: jobstart failed (" .. job_id .. ")", vim.log.levels.ERROR)
    job_id = 0
  end
end

function M.stop()
  if job_id > 0 then
    vim.fn.jobstop(job_id)
    job_id = 0
    ready = false
  end
end

function M.restart()
  M.stop()
  M.start()
end

function M.ensure_started()
  if job_id <= 0 then
    M.start()
  end
end

function M.channel()
  return job_id
end

function M.executable()
  return resolve_executable()
end

function M.call_rpc(method, args)
  M.ensure_started()
  local channel = M.channel()
  if channel <= 0 then
    return
  end
  if args == nil then
    vim.fn.rpcrequest(channel, method)
  else
    vim.fn.rpcrequest(channel, method, args)
  end
end

local function current_dir()
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" then
    return vim.fn.getcwd()
  end
  return vim.fn.fnamemodify(name, ":p:h")
end

local function env_file_entries(dir)
  local entries = {}
  local seen = {}

  local function add(path, name, label)
    if path ~= "" and vim.fn.filereadable(path) == 1 and not seen[path] then
      seen[path] = true
      table.insert(entries, {
        label = label,
        name = name,
        path = path,
      })
    end
  end

  add(dir .. "/.env", "", ".env")
  for _, path in ipairs(vim.fn.globpath(dir, ".env.*", false, true)) do
    local tail = vim.fn.fnamemodify(path, ":t")
    local name = tail:match("^%.env%.(.+)$")
    if name then
      add(path, name, tail)
    end
  end

  table.sort(entries, function(a, b) return a.label < b.label end)
  return entries
end

function M.freight_env_command(arg)
  if arg == nil or arg == "" then
    M.select_env()
  else
    M.call_rpc("FreightEnv", arg)
  end
end

function M.select_env()
  local ok_builtin, _ = pcall(require, "telescope.builtin")
  local ok_pickers, pickers = pcall(require, "telescope.pickers")
  local ok_finders, finders = pcall(require, "telescope.finders")
  local ok_conf, conf = pcall(require, "telescope.config")
  local ok_actions, actions = pcall(require, "telescope.actions")
  local ok_action_state, action_state = pcall(require, "telescope.actions.state")

  if not (ok_builtin and ok_pickers and ok_finders and ok_conf and ok_actions and ok_action_state) then
    vim.notify("freight: Telescope is required for :FreightEnv without an argument", vim.log.levels.ERROR)
    return
  end

  local entries = env_file_entries(current_dir())
  if #entries == 0 then
    vim.notify("freight: no env files found for this buffer", vim.log.levels.INFO)
    return
  end

  pickers.new({}, {
    prompt_title = "Freight env file",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.label,
          ordinal = entry.label,
        }
      end,
    }),
    sorter = conf.values.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if not selection or not selection.value then
          return
        end
        local entry = selection.value
        M.call_rpc("FreightEnvApply", entry.name)
      end)
      return true
    end,
  }):find()
end

function M.ready()
  return ready
end

return M
