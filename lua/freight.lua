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

local function env_entries(dir)
  local entries = {}
  local seen_env = {}
  local seen_file = {}
  local files = {}

  local function add_file(path)
    if path ~= "" and not seen_file[path] and vim.fn.filereadable(path) == 1 then
      seen_file[path] = true
      table.insert(files, path)
    end
  end

  add_file(dir .. "/.env")
  for _, path in ipairs(vim.fn.globpath(dir, ".env.*", false, true)) do
    add_file(path)
    local tail = vim.fn.fnamemodify(path, ":t")
    local name = tail:match("^%.env%.(.+)$")
    if name and name ~= "local" and not seen_env[name] then
      seen_env[name] = true
      table.insert(entries, {
        kind = "environment",
        label = "environment  " .. name,
        name = name,
      })
    end
  end

  table.sort(entries, function(a, b) return a.label < b.label end)
  table.sort(files)

  for _, path in ipairs(files) do
    local source = vim.fn.fnamemodify(path, ":t")
    for _, line in ipairs(vim.fn.readfile(path)) do
      local trimmed = vim.trim(line)
      if trimmed ~= "" and not vim.startswith(trimmed, "#") then
        local key, value = trimmed:match("^%s*([%w_][%w_%.%-]*)%s*=%s*(.*)$")
        if key then
          table.insert(entries, {
            kind = "variable",
            label = key .. " = " .. value .. "  (" .. source .. ")",
            key = key,
            value = value,
          })
        end
      end
    end
  end

  return entries
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

  local entries = env_entries(current_dir())
  if #entries == 0 then
    vim.notify("freight: no .env files found for this buffer", vim.log.levels.INFO)
    return
  end

  pickers.new({}, {
    prompt_title = "Freight environment",
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
        if entry.kind == "environment" then
          M.call_rpc("FreightEnv", entry.name)
        elseif entry.kind == "variable" then
          vim.fn.setreg("+", entry.value)
          vim.notify("freight: copied " .. entry.key .. " to clipboard", vim.log.levels.INFO)
        end
      end)
      return true
    end,
  }):find()
end

function M.ready()
  return ready
end

return M
