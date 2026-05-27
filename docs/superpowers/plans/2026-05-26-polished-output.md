# Polished Output Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Telescope environment picking and polish Freight scratch/response output.

**Architecture:** Keep the current OCaml RPC + scratch-buffer architecture. Lua handles Telescope integration and command UX; OCaml keeps rendering scratch buffers and response text. Changes are split into Lua picker, scratch window chrome, response formatting, and verification/docs.

**Tech Stack:** OCaml, dune, OUnit2, Eio-based Neovim RPC, Lua Neovim APIs, optional Telescope.

---

## File Structure

- Modify: `lua/freight.lua` — add env-name discovery and Telescope picker helpers.
- Modify: `plugin/freight.lua` — route `:FreightEnv` with no args to Lua picker; keep direct RPC call for args.
- Modify: `bin/scratch.ml` — set scratch window-local chrome options after opening buffers.
- Modify: `lib/response.ml` — section response renderers and improve status formatting.
- Modify: `test/test_freight.ml` — add response renderer tests.
- Modify: `README.md` — document Telescope requirement for picker and polished output behavior.

---

### Task 1: Telescope Environment Picker

**Files:**

- Modify: `lua/freight.lua`
- Modify: `plugin/freight.lua`

- [ ] **Step 1: Add Lua env discovery and picker helpers**

In `lua/freight.lua`, add functions that:

```lua
local function current_dir()
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" then
    return vim.fn.getcwd()
  end
  return vim.fn.fnamemodify(name, ":p:h")
end

local function env_names(dir)
  local names = {}
  local seen = {}
  for _, path in ipairs(vim.fn.globpath(dir, ".env.*", false, true)) do
    local tail = vim.fn.fnamemodify(path, ":t")
    local name = tail:match("^%.env%.(.+)$")
    if name and name ~= "local" and not seen[name] then
      seen[name] = true
      table.insert(names, name)
    end
  end
  table.sort(names)
  return names
end

function M.select_env()
  local ok_builtin, builtin = pcall(require, "telescope.builtin")
  local ok_pickers, pickers = pcall(require, "telescope.pickers")
  local ok_finders, finders = pcall(require, "telescope.finders")
  local ok_conf, conf = pcall(require, "telescope.config")
  local ok_actions, actions = pcall(require, "telescope.actions")
  local ok_action_state, action_state = pcall(require, "telescope.actions.state")

  if not (ok_builtin and ok_pickers and ok_finders and ok_conf and ok_actions and ok_action_state) then
    vim.notify("freight: Telescope is required for :FreightEnv without an argument", vim.log.levels.ERROR)
    return
  end

  local names = env_names(current_dir())
  if #names == 0 then
    vim.notify("freight: no .env.<name> files found for this buffer", vim.log.levels.INFO)
    return
  end

  pickers.new({}, {
    prompt_title = "Freight environment",
    finder = finders.new_table({ results = names }),
    sorter = conf.values.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection and selection[1] then
          M.call_rpc("FreightEnv", selection[1])
        end
      end)
      return true
    end,
  }):find()
end
```

Expose `M.call_rpc(method, args)` if it is currently local-only so the picker can reuse it.

- [ ] **Step 2: Route no-arg `FreightEnv` to picker**

In `plugin/freight.lua`, change the `FreightEnv` wrapper so:

```lua
vim.api.nvim_create_user_command("FreightEnv", function(opts)
  if opts.args == "" then
    freight.select_env()
  else
    freight.call_rpc("FreightEnv", opts.args)
  end
end, { nargs = "?", desc = "Show or select the active Freight environment" })
```

- [ ] **Step 3: Manual/headless checks**

Run:

```sh
nvim --clean -u NONE -c 'set rtp+=.' -c 'runtime plugin/freight.lua' -c 'command FreightEnv' -c 'qa'
```

Expected: `FreightEnv` command exists.

Run a headless Lua call with Telescope absent if feasible:

```sh
nvim --clean -u NONE -c 'set rtp+=.' -c 'runtime plugin/freight.lua' -c 'lua require("freight").select_env()' -c 'qa'
```

Expected: no crash; notification path is exercised.

- [ ] **Step 4: Commit**

```sh
jj describe -m "feat(plugin): add telescope environment picker"
jj new
```

---

### Task 2: Hide Scratch Buffer Line Numbers

**Files:**

- Modify: `bin/scratch.ml`

- [ ] **Step 1: Add window chrome helper**

Add a helper in `bin/scratch.ml`:

```ocaml
let set_window_chrome ~call =
  let set name value =
    ignore (call "nvim_set_option_value"
      [ Msgpck.String name; value; Msgpck.Map [ (Msgpck.String "scope", Msgpck.String "local") ] ])
  in
  set "number" (Msgpck.Bool false);
  set "relativenumber" (Msgpck.Bool false);
  set "signcolumn" (Msgpck.String "no");
  set "foldcolumn" (Msgpck.String "0")
```

- [ ] **Step 2: Apply after opening scratch window**

In `show`, after:

```ocaml
ignore (call "nvim_command"
  [ Msgpck.String (Printf.sprintf "vsplit | buffer %d" handle_int) ]);
```

call:

```ocaml
set_window_chrome ~call;
```

- [ ] **Step 3: Verify build**

Run:

```sh
opam exec -- dune build @install
```

Expected: pass.

- [ ] **Step 4: Commit**

```sh
jj describe -m "fix(ui): hide scratch buffer line numbers"
jj new
```

---

### Task 3: Polish Response Renderers

**Files:**

- Modify: `lib/response.ml`
- Modify: `test/test_freight.ml`

- [ ] **Step 1: Add failing response rendering tests**

In `test/test_freight.ml`, add tests asserting:

```ocaml
let test_response_render_all_has_sections _ =
  let response = sample_response ~body:"{\"ok\":true}" () in
  let lines = Freight.Response.render_all response in
  assert_bool "has status" (List.exists (( = ) "HTTP 200 OK · 123 ms") lines);
  assert_bool "has headers heading" (List.exists (( = ) "Headers") lines);
  assert_bool "has body heading" (List.exists (( = ) "Body") lines)

let test_response_render_headers_has_heading _ =
  let response = sample_response ~body:"" () in
  let lines = Freight.Response.render_headers response in
  assert_equal [ "HTTP 200 OK · 123 ms"; ""; "Headers"; "Content-Type: application/json" ] lines
```

Use or adapt existing response fixtures in the file.

- [ ] **Step 2: Run focused test and verify failure**

Run:

```sh
opam exec -- dune exec test/test_freight.exe
```

Expected: new tests fail because current status uses parentheses and no section headings.

- [ ] **Step 3: Update response renderers**

In `lib/response.ml`, introduce:

```ocaml
let render_status response =
  Printf.sprintf "HTTP %d %s · %d ms" response.Ast.status response.status_text response.duration_ms

let render_header_lines response =
  List.map (fun (name, value) -> Printf.sprintf "%s: %s" name value) response.headers
```

Make `render`, `render_headers`, and `render_all` use sectioned output:

```ocaml
let render response = render_all response

let render_body response =
  [ pretty_print_body (detect_content_type response) response.body ]

let render_headers response =
  render_status response :: "" :: "Headers" :: render_header_lines response

let render_all response =
  render_headers response @ [ ""; "Body"; pretty_print_body (detect_content_type response) response.body ]
```

Preserve existing function names and signatures.

- [ ] **Step 4: Update loading/error strings in `bin/handlers.ml`**

Change:

```ocaml
~lines:[ "Loading…" ]
```

to:

```ocaml
~lines:[ "Running request…" ]
```

Change curl execution errors to:

```ocaml
~lines:[ "Request failed"; msg ]
```

Change response parse errors to:

```ocaml
~lines:[ "Response parse failed"; msg ]
```

- [ ] **Step 5: Verify tests**

Run:

```sh
opam exec -- dune exec test/test_freight.exe
opam exec -- dune runtest
```

Expected: pass.

- [ ] **Step 6: Commit**

```sh
jj describe -m "feat(response): polish scratch output formatting"
jj new
```

---

### Task 4: Document Polished UI Behavior

**Files:**

- Modify: `README.md`

- [ ] **Step 1: Add Telescope note**

Document that `:FreightEnv` without an argument requires Telescope and opens an environment picker.

- [ ] **Step 2: Mention scratch chrome/output polish**

Document response views as clean scratch buffers with body/header/all/verbose mappings.

- [ ] **Step 3: Verify docs mention Telescope**

Run:

```sh
grep -q Telescope README.md
```

Expected: exit code 0.

- [ ] **Step 4: Commit**

```sh
jj describe -m "docs(readme): document polished freight UI"
jj new
```

---

### Task 5: Final Verification

- [ ] **Step 1: Run full tests**

```sh
opam exec -- dune runtest
```

Expected: pass.

- [ ] **Step 2: Run install build**

```sh
opam exec -- dune build @install
```

Expected: pass.

- [ ] **Step 3: Check jj state**

```sh
jj st
jj log -r 'ancestors(@, 8)'
```

Expected: clean working copy on a new empty change above the feature commits.
