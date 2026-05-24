# Multi-View Response Buffer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Body / Headers / All view switching to the freight response buffer, toggled by `B`, `H`, `A` keymaps inside the buffer.

**Architecture:** Add three pure render functions to `lib/response.ml` (`render_body`, `render_headers`, `render_all`) and expose them via `lib/response.mli`. Store the last `Ast.response` in `State` so any view switch can re-render without re-running the request. Add a `FreightView` RPC command that takes a view name, looks up the stored response, and calls `Scratch.update` with the appropriate render. Wire the keymaps into the response buffer immediately after it is first shown in `freight_run`.

**Tech Stack:** OCaml, OUnit2 tests, existing Freight library + bin layer, Neovim msgpack-rpc.

---

## File structure

- Modify: `lib/response.ml` — add `render_body`, `render_headers`, `render_all`
- Modify: `lib/response.mli` — expose the three new render functions
- Modify: `bin/state.ml` + `bin/state.mli` — add `mutable last_response : Ast.response option`
- Modify: `bin/handlers.ml` — store response after run; add `freight_view` handler; set keymaps after showing response buffer
- Modify: `bin/main.ml` — register `FreightView` command; dispatch `freight_view`
- Modify: `test/test_freight.ml` — tests for `render_body`, `render_headers`, `render_all`

---

### Task 1: Add render_body, render_headers, render_all to lib/response.ml

**Files:**

- Modify: `lib/response.mli`
- Modify: `lib/response.ml`
- Modify: `test/test_freight.ml`

The existing `render` function produces: status line, all headers, blank line, pretty-printed body. The three new functions are:

- `render_body response` — pretty-printed body only (no status, no headers)
- `render_headers response` — status line + all headers (no body)
- `render_all response` — identical to current `render` (status + headers + blank + body)

The filetype for `render_body` should remain the content-type filetype (json/html/etc). `render_headers` is always `"text"`. `render_all` uses the content-type filetype.

Since the render functions themselves don't decide filetype, the caller (`freight_view`) will handle that. The functions just return `string list`.

- [ ] **Step 1: Write failing tests**

Read `test/test_freight.ml`. Find `test_render_pretty_prints_json_response` to understand the existing response fixture — use the same fixture. Insert these tests after `test_render_falls_back_to_invalid_json_body`:

```ocaml
let test_render_body _ =
  let request = {
    Freight.Ast.name = None;
    method_ = Freight.Ast.Get;
    url = "https://httpbin.org/get";
    headers = [];
    body = Freight.Ast.Body_none;
  } in
  let response = {
    Freight.Ast.status = 200;
    status_text = "OK";
    headers = [ ("content-type", "application/json") ];
    body = {|{"id":1}|};
    duration_ms = 42;
    request;
  } in
  let lines = Freight.Response.render_body response in
  assert_equal [ "{\n  \"id\": 1\n}" ] lines

let test_render_headers _ =
  let request = {
    Freight.Ast.name = None;
    method_ = Freight.Ast.Get;
    url = "https://httpbin.org/get";
    headers = [];
    body = Freight.Ast.Body_none;
  } in
  let response = {
    Freight.Ast.status = 200;
    status_text = "OK";
    headers = [ ("content-type", "application/json"); ("x-foo", "bar") ];
    body = {|{"id":1}|};
    duration_ms = 100;
    request;
  } in
  let lines = Freight.Response.render_headers response in
  assert_equal
    [ "HTTP 200 OK (100 ms)"; "content-type: application/json"; "x-foo: bar" ]
    lines

let test_render_all _ =
  let request = {
    Freight.Ast.name = None;
    method_ = Freight.Ast.Get;
    url = "https://httpbin.org/get";
    headers = [];
    body = Freight.Ast.Body_none;
  } in
  let response = {
    Freight.Ast.status = 200;
    status_text = "OK";
    headers = [ ("content-type", "application/json") ];
    body = {|{"id":1}|};
    duration_ms = 42;
    request;
  } in
  let lines = Freight.Response.render_all response in
  assert_equal
    (Freight.Response.render response)
    lines
```

Register in the suite list (find the `"render_pretty_prints_json_response"` entry and add after `"render_falls_back_to_invalid_json_body"`):

```ocaml
"render_body" >:: test_render_body;
"render_headers" >:: test_render_headers;
"render_all" >:: test_render_all;
```

- [ ] **Step 2: Run tests to verify they fail**

```
opam exec --switch freight-vcaml -- dune test test/test_freight.exe 2>&1 | tail -10
```

Expected: FAIL — `Unbound value Freight.Response.render_body`

- [ ] **Step 3: Add vals to lib/response.mli**

Append after `val render`:

```ocaml
val render_body : Ast.response -> string list
(** Pretty-printed body only. *)

val render_headers : Ast.response -> string list
(** Status line and all response headers, no body. *)

val render_all : Ast.response -> string list
(** Status line, headers, blank line, pretty-printed body. Identical to [render]. *)
```

- [ ] **Step 4: Implement in lib/response.ml**

Append after the existing `render` function:

```ocaml
let render_body response =
  let body = pretty_print_body (detect_content_type response) response.Ast.body in
  [ body ]

let render_headers response =
  let status_line =
    Printf.sprintf "HTTP %d %s (%d ms)" response.Ast.status response.status_text
      response.duration_ms
  in
  let header_lines =
    List.map (fun (name, value) -> Printf.sprintf "%s: %s" name value) response.headers
  in
  status_line :: header_lines

let render_all response = render response
```

- [ ] **Step 5: Run tests to verify they pass**

```
opam exec --switch freight-vcaml -- dune test test/test_freight.exe 2>&1 | tail -5
```

Expected: all tests pass, count increases by 3.

- [ ] **Step 6: Commit**

```
jj describe -m "feat(response): add render_body, render_headers, render_all views"
jj new
```

---

### Task 2: Store last response in State

**Files:**

- Modify: `bin/state.ml`
- Modify: `bin/state.mli`

No tests for State directly (it's a thin mutable record — tested implicitly via integration).

- [ ] **Step 1: Update bin/state.mli**

Replace the entire file with:

```ocaml
type t = {
  mutable active_env : string option;
  mutable env : Freight.Env.t;
  mutable last_response : Freight.Ast.response option;
}

val create : unit -> t
val set_active_env : t -> string option -> unit
```

- [ ] **Step 2: Update bin/state.ml**

Replace the entire file with:

```ocaml
type t = {
  mutable active_env : string option;
  mutable env : Freight.Env.t;
  mutable last_response : Freight.Ast.response option;
}

let create () = { active_env = None; env = Freight.Env.empty; last_response = None }

let set_active_env state env_name =
  state.active_env <- env_name
```

- [ ] **Step 3: Build**

```
opam exec --switch freight-vcaml -- dune build bin/main.exe 2>&1
```

Expected: clean.

- [ ] **Step 4: Commit**

```
jj describe -m "feat(state): store last_response for view switching"
jj new
```

---

### Task 3: Wire FreightView into handlers and main

**Files:**

- Modify: `bin/handlers.ml`
- Modify: `bin/main.ml`

This task:
1. In `freight_run`, store the parsed response into `state.last_response` and set keymaps `B`, `H`, `A` on the response buffer after `Scratch.update`.
2. Add `freight_view` handler that reads `state.last_response`, picks the right render function by view name, and calls `Scratch.update` on the named buffer.
3. Register `FreightView` command in `main.ml` and dispatch it.

The keymaps are set with `nvim_buf_set_keymap`. The `FreightView` command takes a required single argument (the view name: `Body`, `Headers`, `All`).

The response buffer name is `Freight.Buffer.buffer_name request` — but `freight_view` doesn't have the request at hand. Store the buffer name in state alongside the response, OR look up the buffer by name. Looking up by name is simpler: use `nvim_call rpc "nvim_command" "buffer freight://response/..."` — but we don't know the name in `freight_view`. 

**Simplest approach:** Also store the buffer name (as a string) in state.

Update `bin/state.mli` and `bin/state.ml` to add `mutable response_buf_name : string option`. Then in `freight_run` store it. In `freight_view` look up the buffer handle by iterating buffers, or — simpler — just call `nvim_buf_get_number` by name via a vimscript `bufnr(name)` call.

**Exact approach for freight_view:**

```ocaml
let freight_view ~rpc state view_name =
  match state.State.last_response with
  | None -> show_error ~rpc "No response to view."
  | Some response ->
    match state.State.response_buf_name with
    | None -> show_error ~rpc "No response buffer."
    | Some buf_name ->
      let lines, filetype = match view_name with
        | "Body" ->
          let ct = Freight.Response.detect_content_type response in
          let ft = Freight.Buffer.filetype_of_content_type ct in
          (Freight.Response.render_body response, ft)
        | "Headers" ->
          (Freight.Response.render_headers response, "text")
        | _ ->
          let ct = Freight.Response.detect_content_type response in
          let ft = Freight.Buffer.filetype_of_content_type ct in
          (Freight.Response.render_all response, ft)
      in
      (* look up the buffer handle by name via vimscript bufnr() *)
      match%bind nvim_call rpc "nvim_eval"
        [ Msgpck.String (Printf.sprintf "bufnr('%s')" buf_name) ] with
      | Msgpck.Int n when n >= 0 ->
        let buf = Msgpck.Int n in
        Scratch.update ~rpc buf ~filetype ~lines
      | _ -> show_error ~rpc "Response buffer not found."
```

For setting keymaps, after the `Scratch.update` call in `freight_run` (inside the `don't_wait_for` block), add:

```ocaml
let set_keymap buf key view =
  nvim_call rpc "nvim_buf_set_keymap"
    [ buf
    ; Msgpck.String "n"
    ; Msgpck.String key
    ; Msgpck.String (Printf.sprintf ":FreightView %s<CR>" view)
    ; Msgpck.Map [ (Msgpck.String "noremap", Msgpck.Bool true)
                 ; (Msgpck.String "silent", Msgpck.Bool true) ]
    ]
in
```

- [ ] **Step 1: Update state to hold response_buf_name**

In `bin/state.mli`, add `mutable response_buf_name : string option` to the type and keep everything else the same:

```ocaml
type t = {
  mutable active_env : string option;
  mutable env : Freight.Env.t;
  mutable last_response : Freight.Ast.response option;
  mutable response_buf_name : string option;
}

val create : unit -> t
val set_active_env : t -> string option -> unit
```

In `bin/state.ml`, add the field to `create`:

```ocaml
type t = {
  mutable active_env : string option;
  mutable env : Freight.Env.t;
  mutable last_response : Freight.Ast.response option;
  mutable response_buf_name : string option;
}

let create () = {
  active_env = None;
  env = Freight.Env.empty;
  last_response = None;
  response_buf_name = None;
}

let set_active_env state env_name =
  state.active_env <- env_name
```

- [ ] **Step 2: Add freight_view to bin/handlers.ml**

First, read the current `bin/handlers.ml` to find the exact current content of `freight_run`. The `freight_run` function currently ends with the `don't_wait_for` block. Inside that block, after the successful `Scratch.update ~rpc loading_buf ~filetype ~lines:...` call, store the response and buffer name, then set keymaps.

Add a local `set_keymap` helper inside the `don't_wait_for` body, and store state fields. The full updated `freight_run` (`Ok response ->` branch inside `Monitor.try_with`):

```ocaml
| Ok response ->
  let filetype =
    Freight.Buffer.filetype_of_content_type
      (Freight.Response.detect_content_type response)
  in
  let req_name = Option.value request.Freight.Ast.name ~default:"" in
  state.State.env <- Freight.Chaining.inject ~name:req_name response state.State.env;
  state.State.last_response <- Some response;
  state.State.response_buf_name <- Some name;
  let%bind () = Scratch.update ~rpc loading_buf ~filetype
    ~lines:(Freight.Response.render response) in
  let set_keymap key view =
    let%map _ = nvim_call rpc "nvim_buf_set_keymap"
      [ loading_buf
      ; Msgpck.String "n"
      ; Msgpck.String key
      ; Msgpck.String (Printf.sprintf ":FreightView %s<CR>" view)
      ; Msgpck.Map
          [ (Msgpck.String "noremap", Msgpck.Bool true)
          ; (Msgpck.String "silent", Msgpck.Bool true) ]
      ]
    in ()
  in
  let%bind () = set_keymap "B" "Body" in
  let%bind () = set_keymap "H" "Headers" in
  set_keymap "A" "All"
```

Then add `freight_view` after `freight_run`:

```ocaml
let freight_view ~rpc state view_name =
  match state.State.last_response with
  | None -> show_error ~rpc "No response to view."
  | Some response ->
    match state.State.response_buf_name with
    | None -> show_error ~rpc "No response buffer."
    | Some buf_name ->
      let lines, filetype =
        match view_name with
        | "Body" ->
          let ct = Freight.Response.detect_content_type response in
          let ft = Freight.Buffer.filetype_of_content_type ct in
          (Freight.Response.render_body response, ft)
        | "Headers" ->
          (Freight.Response.render_headers response, "text")
        | _ ->
          let ct = Freight.Response.detect_content_type response in
          let ft = Freight.Buffer.filetype_of_content_type ct in
          (Freight.Response.render_all response, ft)
      in
      (match%bind nvim_call rpc "nvim_eval"
        [ Msgpck.String (Printf.sprintf "bufnr('%s')" buf_name) ] with
      | Msgpck.Int n when n >= 0 ->
        let buf = Msgpck.Int n in
        Scratch.update ~rpc buf ~filetype ~lines
      | _ -> show_error ~rpc "Response buffer not found.")
```

- [ ] **Step 3: Register FreightView in bin/main.ml**

In `register_commands`, add after `FreightInspect`:

```ocaml
let%bind () = cmd "FreightView" `Required "FreightView" in
```

Change the `cmd` helper to also handle `` `Required ``:

Currently the helper has:
```ocaml
let cmd name nargs rpc_method =
  let nargs_str = match nargs with
    | `None -> ""
    | `Optional -> " -nargs=?"
  in
  let call_str = match nargs with
    | `None -> Printf.sprintf "call rpcrequest(%d, '%s')" channel rpc_method
    | `Optional -> Printf.sprintf "call rpcrequest(%d, '%s', <q-args>)" channel rpc_method
  in
```

Add `` `Required `` to both matches:

```ocaml
let cmd name nargs rpc_method =
  let nargs_str = match nargs with
    | `None -> ""
    | `Optional -> " -nargs=?"
    | `Required -> " -nargs=1"
  in
  let call_str = match nargs with
    | `None -> Printf.sprintf "call rpcrequest(%d, '%s')" channel rpc_method
    | `Optional -> Printf.sprintf "call rpcrequest(%d, '%s', <q-args>)" channel rpc_method
    | `Required -> Printf.sprintf "call rpcrequest(%d, '%s', <q-args>)" channel rpc_method
  in
```

In `dispatch`, add a case for `FreightView`:

```ocaml
| "FreightView" ->
  let view_name = match params with
    | Msgpck.String s :: _ -> s
    | _ -> "All"
  in
  let%map () = Handlers.freight_view ~rpc state view_name in
  Msgpck.Nil
```

- [ ] **Step 4: Build**

```
opam exec --switch freight-vcaml -- dune build bin/main.exe 2>&1
```

Expected: clean.

- [ ] **Step 5: Smoke test**

Restart Neovim. Open an `.http` file, run `:FreightRun`. In the response buffer:
- Press `H` — should show only status line + headers, filetype text
- Press `B` — should show only the pretty-printed body, filetype json
- Press `A` — should show full response (status + headers + body)

- [ ] **Step 6: Commit**

```
jj describe -m "feat(handlers): FreightView command with B/H/A keymaps for response buffer views"
jj new
```
