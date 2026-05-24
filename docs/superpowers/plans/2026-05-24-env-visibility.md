# Env Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `:FreightEnv [name]` show a useful scratch buffer: the active env name, all loaded key=value pairs, and any `{{variables}}` in the current buffer that are unresolved (missing from env).

**Architecture:** Add two pure functions to `lib/env.ml`: `to_list` (enumerate all key=value pairs) and `unresolved` (scan a source string and return variable names not present in the env). Wire both into `bin/handlers.ml`'s `freight_env` handler and render through `bin/request_view.ml`.

**Tech Stack:** OCaml, Re (already used for substitution regex in env.ml), OUnit2 tests, existing Freight library + bin layer.

---

## File structure

- Modify: `lib/env.mli` — add `val to_list` and `val unresolved`
- Modify: `lib/env.ml` — implement both; reuse existing `variable` regex for `unresolved`
- Modify: `test/test_freight.ml` — add tests for both new functions
- Modify: `bin/request_view.ml` — add `render_env` that formats the env view
- Modify: `bin/handlers.ml` — update `freight_env` to fetch buffer source, call `unresolved`, render full view

---

### Task 1: Add `to_list` and `unresolved` to Env

**Files:**

- Modify: `lib/env.mli`
- Modify: `lib/env.ml`
- Modify: `test/test_freight.ml`

- [ ] **Step 1: Write failing tests**

Open `test/test_freight.ml`. Find the env test section (look for `test_env_substitute_unknown_preserved`). Add these two tests immediately after the existing env tests:

```ocaml
let test_env_to_list _ =
  let env = Freight.Env.of_list [ ("b", "2"); ("a", "1"); ("c", "3") ] in
  let pairs = Freight.Env.to_list env in
  (* Map.Make gives sorted order *)
  assert_equal [ ("a", "1"); ("b", "2"); ("c", "3") ] pairs

let test_env_unresolved _ =
  let env = Freight.Env.of_list [ ("host", "https://api.example.com") ] in
  let source = "GET {{host}}/users\nAuthorization: Bearer {{token}}\nX-Id: {{request_id}}" in
  let missing = Freight.Env.unresolved env source in
  assert_equal [ "request_id"; "token" ] missing
```

Note: `unresolved` returns variable names sorted and deduplicated.

- [ ] **Step 2: Register tests in the test suite**

In `test/test_freight.ml`, find where tests are added to the suite (look for `"test_env_substitute_unknown_preserved" >:: test_env_substitute_unknown_preserved`). Add:

```ocaml
"test_env_to_list" >:: test_env_to_list;
"test_env_unresolved" >:: test_env_unresolved;
```

- [ ] **Step 3: Run tests to verify they fail**

```
opam exec --switch freight-vcaml -- dune test test/test_freight.exe 2>&1 | tail -10
```

Expected: FAIL with `Unbound value Freight.Env.to_list` (or similar).

- [ ] **Step 4: Add vals to env.mli**

Append to `lib/env.mli` after `val substitute`:

```ocaml
val to_list : t -> (string * string) list
(** All key-value pairs in the env, sorted by key. *)

val unresolved : t -> string -> string list
(** [unresolved env source] returns the sorted, deduplicated list of
    variable names referenced in [source] via [{{name}}] syntax that
    are not present in [env]. *)
```

- [ ] **Step 5: Implement both in env.ml**

Append to `lib/env.ml` after `substitute`:

```ocaml
let to_list env = String_map.bindings env

let unresolved env source =
  let seen = Hashtbl.create 8 in
  Re.all variable source
  |> List.filter_map (fun group ->
      let key = Re.Group.get group 1 in
      match find env key with
      | Some _ -> None
      | None ->
        if Hashtbl.mem seen key then None
        else begin Hashtbl.add seen key (); Some key end)
  |> List.sort String.compare
```

- [ ] **Step 6: Run tests to verify they pass**

```
opam exec --switch freight-vcaml -- dune test test/test_freight.exe 2>&1 | tail -5
```

Expected: all tests pass, count increases by 2.

- [ ] **Step 7: Commit**

```
jj describe -m "feat(env): add to_list and unresolved for env visibility"
jj new
```

---

### Task 2: Render the env view

Add `render_env` to `bin/request_view.ml`. This function takes the active env name, the list of key=value pairs, and unresolved variable names, and produces a `string list` for `Scratch.show`.

**Files:**

- Modify: `bin/request_view.ml`

- [ ] **Step 1: Append render_env to request_view.ml**

```ocaml
let render_env ~active_env ~pairs ~unresolved =
  let label = match active_env with Some n -> n | None -> "(none)" in
  let vars_section =
    match pairs with
    | [] -> [ "Variables: (none)" ]
    | _ ->
      "Variables:"
      :: List.map (fun (k, v) -> Printf.sprintf "  %s = %s" k v) pairs
  in
  let unresolved_section =
    match unresolved with
    | [] -> [ "Unresolved: (none)" ]
    | names ->
      "Unresolved:"
      :: List.map (fun name -> Printf.sprintf "  {{%s}}" name) names
  in
  [ "Freight Env"; ""; "Active: " ^ label; "" ]
  @ vars_section
  @ [ "" ]
  @ unresolved_section
```

- [ ] **Step 2: Build**

```
opam exec --switch freight-vcaml -- dune build bin/main.exe 2>&1
```

Expected: clean.

- [ ] **Step 3: Commit**

```
jj describe -m "feat(request_view): add render_env for env visibility view"
jj new
```

---

### Task 3: Wire freight_env handler

Update `freight_env` in `bin/handlers.ml` to fetch the current buffer source, compute unresolved variables, and show the full env view instead of just the active env label.

**Files:**

- Modify: `bin/handlers.ml`

Current `freight_env`:

```ocaml
let freight_env ~rpc state arg =
  let env_name =
    match arg with
    | Some s when not (String.is_empty s) -> Some s
    | _ -> None
  in
  State.set_active_env state env_name;
  let%bind buf = nvim_call rpc "nvim_get_current_buf" [] in
  let%bind dir_opt = get_buf_path rpc buf in
  (match dir_opt with
   | Some dir -> state.State.env <- Freight.Env.load ~dir ~active_env:env_name
   | None -> ());
  let label = match env_name with Some n -> n | None -> "(none)" in
  Scratch.show ~rpc ~name:"freight://info" ~filetype:"text"
    ~lines:(Request_view.render_message ~title:"Env"
       ~body:[ Printf.sprintf "Active env: %s" label ])
```

- [ ] **Step 1: Replace freight_env**

```ocaml
let freight_env ~rpc state arg =
  let env_name =
    match arg with
    | Some s when not (String.is_empty s) -> Some s
    | _ -> None
  in
  State.set_active_env state env_name;
  let%bind buf = nvim_call rpc "nvim_get_current_buf" [] in
  let%bind dir_opt = get_buf_path rpc buf in
  (match dir_opt with
   | Some dir -> state.State.env <- Freight.Env.load ~dir ~active_env:env_name
   | None -> ());
  let%bind lines_msg =
    nvim_call rpc "nvim_buf_get_lines"
      [ buf; Msgpck.Int 0; Msgpck.Int (-1); Msgpck.Bool false ]
  in
  let source =
    match lines_msg with
    | Msgpck.List xs ->
      List.filter_map xs ~f:(function Msgpck.String s -> Some s | _ -> None)
      |> String.concat ~sep:"\n"
    | _ -> ""
  in
  let pairs = Freight.Env.to_list state.State.env in
  let unresolved = Freight.Env.unresolved state.State.env source in
  Scratch.show ~rpc ~name:"freight://env" ~filetype:"text"
    ~lines:(Request_view.render_env ~active_env:env_name ~pairs ~unresolved)
```

- [ ] **Step 2: Build**

```
opam exec --switch freight-vcaml -- dune build bin/main.exe 2>&1
```

Expected: clean.

- [ ] **Step 3: Smoke test**

Restart Neovim. Open a `.http` file that references `{{base_url}}` and `{{token}}`. Create a `.env` file in the same directory with `base_url=https://api.example.com`. Run `:FreightEnv`.

Expected scratch buffer:
```
Freight Env

Active: (none)

Variables:
  base_url = https://api.example.com

Unresolved:
  {{token}}
```

Run `:FreightEnv dev` (assuming no `.env.dev` exists):

Expected: same variables (only `.env` loaded), active changes to `dev`.

- [ ] **Step 4: Commit**

```
jj describe -m "feat(handlers): FreightEnv shows loaded vars and unresolved references"
jj new
```
