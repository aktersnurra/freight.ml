# Request History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep a bounded ring buffer of recent (request, response, verbose) triples in plugin state, browsable via `:FreightHistory` which opens a picker and re-displays any past response.

**Architecture:** History is stored as a plain list (capped at 50) on `State.t`. Each entry pairs the `Ast.request` with its `Ast.response` and raw verbose string. `freight_run` appends to history after a successful response. `FreightHistory` renders a summary list in a new scratch buffer; selecting an entry (with `<CR>`) re-displays that response in the response buffer using the existing `freight_view` machinery.

**Tech Stack:** OCaml, existing Eio effects architecture, existing `Scratch`/`Freight_effect` layer. No new dependencies.

---

## File Structure

- **Modify:** `bin/state.ml` + `bin/state.mli` — add `history` list and `push_history` function
- **Modify:** `bin/handlers.ml` — append to history in `freight_run`, add `freight_history` handler
- **Modify:** `bin/handlers.mli` — export `freight_history`
- **Modify:** `bin/request_view.ml` — add `render_history` for the picker list
- **Modify:** `bin/main.ml` — register `FreightHistory` command and dispatch it
- **Modify:** `test/test_handlers.ml` — tests for history accumulation and `freight_history`
- **Modify:** `test/test_runtime_fake.ml` — no change needed (Show_float not needed; history uses existing Show_scratch + Set_keymap)

---

### Task 1: History type and state

Add a `history_entry` type and a bounded `push_history` to `State`.

**Files:**
- Modify: `bin/state.ml`
- Modify: `bin/state.mli`

- [ ] **Step 1: Write failing test**

Add to `test/test_handlers.ml` (after the existing handler tests, before `let () =`):

```ocaml
(* history *)

let test_push_history _ =
  let state = State.create () in
  let req = { Freight.Ast.name = Some "r1"; method_ = Get;
               url = "https://example.com"; headers = []; body = Body_none } in
  let resp = { Freight.Ast.status = 200; status_text = "OK";
               headers = []; body = ""; duration_ms = 1 } in
  State.push_history state req resp "verbose";
  assert_equal 1 (List.length state.State.history);
  let entry = List.hd state.State.history in
  assert_equal req entry.State.request;
  assert_equal resp entry.State.response;
  assert_equal "verbose" entry.State.verbose

let test_push_history_cap _ =
  let state = State.create () in
  let req = { Freight.Ast.name = None; method_ = Get;
               url = "https://example.com"; headers = []; body = Body_none } in
  let resp = { Freight.Ast.status = 200; status_text = "OK";
               headers = []; body = ""; duration_ms = 1 } in
  for i = 1 to 55 do
    State.push_history state req { resp with Freight.Ast.body = string_of_int i } "v"
  done;
  assert_equal 50 (List.length state.State.history);
  (* most recent is head *)
  assert_equal "55" (List.hd state.State.history).State.response.Freight.Ast.body
```

Also add to the test suite list at the bottom:

```ocaml
"push_history" >:: test_push_history;
"push_history_cap" >:: test_push_history_cap;
```

- [ ] **Step 2: Run test to verify it fails**

```bash
opam exec --switch freight-vcaml -- dune build @test/runtest 2>&1 | head -20
```

Expected: compile error — `State.history`, `State.push_history`, `State.request`, `State.response`, `State.verbose` unbound.

- [ ] **Step 3: Add history_entry type and push_history to state.ml**

Replace entire `bin/state.ml` with:

```ocaml
type history_entry = {
  request : Freight.Ast.request;
  response : Freight.Ast.response;
  verbose : string;
}

type t = {
  mutable active_env : string option;
  mutable env : Freight.Env.t;
  mutable last_response : Freight.Ast.response option;
  mutable response_buf : Freight_effect.buffer_id option;
  mutable response_buf_name : string option;
  mutable verbose_output : string option;
  mutable history : history_entry list;
}

let history_cap = 50

let create () = {
  active_env = None;
  env = Freight.Env.empty;
  last_response = None;
  response_buf = None;
  response_buf_name = None;
  verbose_output = None;
  history = [];
}

let set_active_env state env_name =
  state.active_env <- env_name

let push_history state request response verbose =
  let entry = { request; response; verbose } in
  let entries = entry :: state.history in
  state.history <-
    if List.length entries > history_cap then
      List.filteri (fun i _ -> i < history_cap) entries
    else
      entries
```

- [ ] **Step 4: Update bin/state.mli**

Replace entire `bin/state.mli` with:

```ocaml
type history_entry = {
  request : Freight.Ast.request;
  response : Freight.Ast.response;
  verbose : string;
}

type t = {
  mutable active_env : string option;
  mutable env : Freight.Env.t;
  mutable last_response : Freight.Ast.response option;
  mutable response_buf : Freight_effect.buffer_id option;
  mutable response_buf_name : string option;
  mutable verbose_output : string option;
  mutable history : history_entry list;
}

val create : unit -> t
val set_active_env : t -> string option -> unit
val push_history : t -> Freight.Ast.request -> Freight.Ast.response -> string -> unit
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
opam exec --switch freight-vcaml -- dune build @test/runtest 2>&1
```

Expected: all tests pass including the two new ones.

- [ ] **Step 6: Commit**

```bash
jj describe -m "feat(history): history_entry type and push_history on State" && jj new
```

---

### Task 2: Append to history in freight_run

After a successful curl response, push the (request, response, verbose) triple to history.

**Files:**
- Modify: `bin/handlers.ml`

- [ ] **Step 1: Write failing test**

Add to `test/test_handlers.ml` after the existing `freight_run` tests:

```ocaml
let test_freight_run_appends_history _ =
  let raw_response =
    "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nhello"
  in
  let config =
    { Test_runtime_fake.default_config with
      buffer_lines = [ "GET https://example.com" ]
    ; curl_result = Ok raw_response
    ; fork_mode = `Run_immediately
    }
  in
  let state = State.create () in
  let (), _calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_run state
  in
  assert_equal 1 (List.length state.State.history)
```

Add `"freight_run_appends_history" >:: test_freight_run_appends_history;` to the suite.

- [ ] **Step 2: Run test to verify it fails**

```bash
opam exec --switch freight-vcaml -- dune build @test/runtest 2>&1 | tail -10
```

Expected: test fails — history is empty (length 0, expected 1).

- [ ] **Step 3: Add push_history call in handlers.ml**

In `bin/handlers.ml`, inside `freight_run`, in the `Ok response` branch after setting `state.State.verbose_output`:

Find this block (around line 147–154):

```ocaml
            state.State.env <-
              Freight.Chaining.inject ~name:req_name response state.State.env;
            state.State.last_response <- Some response;
            state.State.response_buf <- Some loading_buf;
            state.State.response_buf_name <- Some name;
            state.State.verbose_output <- Some verbose_raw;
```

Add one line after `state.State.verbose_output <- Some verbose_raw;`:

```ocaml
            State.push_history state request response verbose_raw;
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
opam exec --switch freight-vcaml -- dune build @test/runtest 2>&1
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
jj describe -m "feat(history): append entry to history on successful FreightRun" && jj new
```

---

### Task 3: render_history in request_view.ml

A function that takes the history list and returns lines for the picker buffer — one line per entry, numbered, with method + URL + status + timestamp-like duration.

**Files:**
- Modify: `bin/request_view.ml`

The format of each line:

```
 1  GET  https://example.com           200 OK  (42 ms)
 2  POST https://api.example.com/auth  401 Unauthorized  (11 ms)
```

- [ ] **Step 1: Add render_history to request_view.ml**

Append to `bin/request_view.ml`:

```ocaml
let render_history (entries : State.history_entry list) =
  if entries = [] then
    [ "No requests in history." ]
  else
    List.mapi (fun i { State.request; response; _ } ->
      let n = Printf.sprintf "%2d" (i + 1) in
      let meth = Printf.sprintf "%-6s" (Freight.Ast.method_to_string request.Freight.Ast.method_) in
      let url = request.Freight.Ast.url in
      let status = Printf.sprintf "%d %s" response.Freight.Ast.status response.status_text in
      let ms = Printf.sprintf "(%d ms)" response.duration_ms in
      Printf.sprintf "  %s  %s %s  %s  %s" n meth url status ms
    ) entries
```

- [ ] **Step 2: Build to verify**

```bash
opam exec --switch freight-vcaml -- dune build bin/main.exe 2>&1
```

Expected: clean build.

- [ ] **Step 3: Commit**

```bash
jj describe -m "feat(history): render_history for picker display" && jj new
```

---

### Task 4: freight_history handler

A handler that shows the history picker buffer and wires `<CR>` on each line to restore that entry's response into the response buffer.

**Files:**
- Modify: `bin/handlers.ml`
- Modify: `bin/handlers.mli`

The `<CR>` keymap runs `:FreightViewHistory <line_number><CR>`, which calls a new `freight_view_history` dispatch path. `freight_view_history` takes the 1-based index, looks up the entry in `state.history`, restores `last_response`/`response_buf`/`verbose_output`, and calls `freight_view state "All"` to render it.

- [ ] **Step 1: Add freight_history and freight_view_history to handlers.ml**

In `bin/handlers.ml`, append:

```ocaml
let history_buf_name = "freight://history"

let freight_history state =
  let lines = Request_view.render_history state.State.history in
  let buf =
    Freight_effect.show_scratch
      ~name:history_buf_name
      ~filetype:"freight"
      ~lines
  in
  set_buf_keymaps buf;
  (* Wire <CR> to select the entry under cursor via FreightViewHistory *)
  Freight_effect.set_keymap buf ~key:"<CR>"
    ~command:":execute 'FreightViewHistory ' . line('.')<CR>"

let freight_view_history state line_number =
  let index = line_number - 1 in
  match List.nth_opt state.State.history index with
  | None -> show_error "No history entry at that line."
  | Some entry ->
    let request = entry.State.request in
    let response = entry.State.response in
    let name = Freight.Buffer.buffer_name request in
    let filetype =
      Freight.Buffer.filetype_of_content_type
        (Freight.Response.detect_content_type response)
    in
    state.State.last_response <- Some response;
    state.State.verbose_output <- Some entry.State.verbose;
    (match state.State.response_buf with
     | Some buf ->
       Freight_effect.update_scratch buf
         ~name:state.State.response_buf_name
           |> Option.value ~default:name
         ~filetype
         ~lines:(Freight.Response.render response)
     | None ->
       let buf =
         Freight_effect.show_scratch ~name ~filetype
           ~lines:(Freight.Response.render response)
       in
       set_buf_keymaps buf;
       Freight_effect.set_keymap buf ~key:"B" ~command:":FreightView Body<CR>";
       Freight_effect.set_keymap buf ~key:"H" ~command:":FreightView Headers<CR>";
       Freight_effect.set_keymap buf ~key:"A" ~command:":FreightView All<CR>";
       Freight_effect.set_keymap buf ~key:"V" ~command:":FreightView Verbose<CR>";
       state.State.response_buf <- Some buf;
       state.State.response_buf_name <- Some name)
```

Wait — `update_scratch` takes `~name:string`, not `string option`. Rewrite the `Some buf` branch cleanly:

```ocaml
let freight_view_history state line_number =
  let index = line_number - 1 in
  match List.nth_opt state.State.history index with
  | None -> show_error "No history entry at that line."
  | Some entry ->
    let request = entry.State.request in
    let response = entry.State.response in
    let name = Freight.Buffer.buffer_name request in
    let filetype =
      Freight.Buffer.filetype_of_content_type
        (Freight.Response.detect_content_type response)
    in
    state.State.last_response <- Some response;
    state.State.verbose_output <- Some entry.State.verbose;
    (match state.State.response_buf, state.State.response_buf_name with
     | Some buf, Some buf_name ->
       Freight_effect.update_scratch buf ~name:buf_name ~filetype
         ~lines:(Freight.Response.render response)
     | _ ->
       let buf =
         Freight_effect.show_scratch ~name ~filetype
           ~lines:(Freight.Response.render response)
       in
       set_buf_keymaps buf;
       Freight_effect.set_keymap buf ~key:"B" ~command:":FreightView Body<CR>";
       Freight_effect.set_keymap buf ~key:"H" ~command:":FreightView Headers<CR>";
       Freight_effect.set_keymap buf ~key:"A" ~command:":FreightView All<CR>";
       Freight_effect.set_keymap buf ~key:"V" ~command:":FreightView Verbose<CR>";
       state.State.response_buf <- Some buf;
       state.State.response_buf_name <- Some name)
```

- [ ] **Step 2: Update handlers.mli**

Add to `bin/handlers.mli`:

```ocaml
val freight_history : State.t -> unit
val freight_view_history : State.t -> int -> unit
```

- [ ] **Step 3: Build to verify**

```bash
opam exec --switch freight-vcaml -- dune build bin/main.exe 2>&1
```

Expected: clean build.

- [ ] **Step 4: Write tests**

Add to `test/test_handlers.ml`:

```ocaml
let test_freight_history_empty _ =
  let config = Test_runtime_fake.default_config in
  let state = State.create () in
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_history state
  in
  assert_bool "shows history scratch"
    (has_show_scratch ~name:"freight://history" calls)

let test_freight_history_with_entries _ =
  let config = Test_runtime_fake.default_config in
  let state = State.create () in
  let req = { Freight.Ast.name = Some "r1"; method_ = Get;
               url = "https://example.com"; headers = []; body = Body_none } in
  let resp = { Freight.Ast.status = 200; status_text = "OK";
               headers = []; body = "hello"; duration_ms = 10 } in
  State.push_history state req resp "";
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_history state
  in
  assert_bool "shows history scratch"
    (has_show_scratch ~name:"freight://history" calls)

let test_freight_view_history_no_entry _ =
  let config = Test_runtime_fake.default_config in
  let state = State.create () in
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_view_history state 1
  in
  assert_bool "shows error for missing entry"
    (has_show_scratch ~name:"freight://error" calls)

let test_freight_view_history_restores _ =
  let config = Test_runtime_fake.default_config in
  let state = State.create () in
  let req = { Freight.Ast.name = Some "r1"; method_ = Get;
               url = "https://example.com"; headers = []; body = Body_none } in
  let resp = { Freight.Ast.status = 200; status_text = "OK";
               headers = []; body = "hello"; duration_ms = 10 } in
  State.push_history state req resp "verbose_data";
  let (), _calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_view_history state 1
  in
  assert_equal (Some resp) state.State.last_response;
  assert_equal (Some "verbose_data") state.State.verbose_output
```

Add to the suite list:

```ocaml
"freight_history_empty" >:: test_freight_history_empty;
"freight_history_with_entries" >:: test_freight_history_with_entries;
"freight_view_history_no_entry" >:: test_freight_view_history_no_entry;
"freight_view_history_restores" >:: test_freight_view_history_restores;
```

- [ ] **Step 5: Run tests**

```bash
opam exec --switch freight-vcaml -- dune build @test/runtest 2>&1
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
jj describe -m "feat(history): freight_history and freight_view_history handlers" && jj new
```

---

### Task 5: Register FreightHistory and FreightViewHistory commands in main.ml

**Files:**
- Modify: `bin/main.ml`

- [ ] **Step 1: Register commands**

In `bin/main.ml`, in `register_commands`, add after the last `cmd` call:

```ocaml
  cmd "FreightHistory"     `None     "FreightHistory";
  cmd "FreightViewHistory" `Required "FreightViewHistory"
```

- [ ] **Step 2: Add dispatch cases**

In `bin/main.ml`, in the `dispatch` function, add after the `"FreightHelp"` case:

```ocaml
  | "FreightHistory" ->
    Handlers.freight_history state;
    Msgpck.Nil
  | "FreightViewHistory" ->
    let line_number =
      match params with
      | Msgpck.String s :: _ -> (match int_of_string_opt s with Some n -> n | None -> 0)
      | Msgpck.Int n :: _ -> n
      | _ -> 0
    in
    Handlers.freight_view_history state line_number;
    Msgpck.Nil
```

- [ ] **Step 3: Build**

```bash
opam exec --switch freight-vcaml -- dune build bin/main.exe 2>&1
```

Expected: clean build.

- [ ] **Step 4: Commit**

```bash
jj describe -m "feat(history): register FreightHistory and FreightViewHistory commands" && jj new
```

---

## Self-Review

**Spec coverage:**
- ✅ Bounded ring buffer (cap 50, most recent first) — Task 1 `push_history`
- ✅ Append on successful run — Task 2
- ✅ Picker list display with method/URL/status — Task 3 `render_history`
- ✅ `FreightHistory` command opens picker — Task 4 + 5
- ✅ `<CR>` selects entry and restores response — Task 4 `freight_view_history`
- ✅ Restores into existing response buffer if one exists — Task 4
- ✅ Falls back to new buffer if no response buffer yet — Task 4
- ✅ `freight_view` still works after history restore (last_response + verbose_output set) — Task 4

**Placeholder scan:** None. All code blocks complete.

**Type consistency:**
- `State.history_entry` fields `request`, `response`, `verbose` used consistently across Task 1 (definition), Task 2 (write), Task 3 (read), Task 4 (read) ✅
- `push_history state request response verbose_raw` — `verbose_raw : string` matches `verbose : string` in `history_entry` ✅
- `freight_view_history state line_number` where `line_number : int` — dispatch in Task 5 parses `int_of_string_opt` from the `String` param (Neovim passes ex command args as strings) ✅
- `render_history (entries : State.history_entry list)` — `State.history` is `history_entry list` ✅

**One note:** `render_history` in Task 3 references `State.history_entry` — this creates a dependency from `bin/request_view.ml` on `bin/state.ml`. Both are in the `freight_plugin` library (same dune stanza) so this is fine — no circular dependency.
