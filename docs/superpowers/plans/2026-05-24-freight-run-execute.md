# FreightRun HTTP Execution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `:FreightRun` actually execute the HTTP request with curl and display the response in a scratch buffer, instead of only showing the inspect view.

**Architecture:** Add a `run` function to `Freight.Executor` that spawns curl via `Async.Process` and returns stdout as a string. Wire `freight_run` in `bin/handlers.ml` to call it, parse the output with `Freight.Response.parse_curl_output`, render with `Freight.Response.render`, and show in a `freight://response` scratch buffer. Keep `:FreightInspect` as the separate command that shows curl args without running.

**Tech Stack:** OCaml, Async (Process module via async_unix), Core, Freight.Executor, Freight.Response, existing Nvim_rpc + Scratch layer.

---

## File structure

- Modify: `lib/executor.mli` — add `val run : curl_invocation -> (string, string) result Async.Deferred.t`
- Modify: `lib/executor.ml` — implement `run` using `Async.Process.run`
- Modify: `lib/dune` — add `async` to library dependencies
- Modify: `bin/handlers.ml` — update `freight_run` to execute curl, parse, render response; rename old body to `freight_inspect_impl` and call from `freight_inspect`
- Modify: `bin/request_view.ml` — add `render_response` that wraps `Freight.Response.render`

---

### Task 1: Add `run` to Executor

The pure `curl_invocation` type already has `args` and `env`. We add a `run` function that spawns curl with those args and returns its combined stdout.

**Files:**

- Modify: `lib/executor.mli`
- Modify: `lib/executor.ml`
- Modify: `lib/dune`

- [ ] **Step 1: Add `async` to lib/dune**

Current `lib/dune` (read it to confirm current deps, then add `async`):

```lisp
(library
 (name freight)
 (libraries angstrom yojson re async)
 (preprocess (pps ppx_jane))
 (flags (:standard -w @A-4-33-40-41-42-43-34-44)))
```

Run: `opam exec --switch freight-vcaml -- dune build lib/ 2>&1`
Expected: clean build (async was already a transitive dep; making it explicit just enables direct use)

- [ ] **Step 2: Add val to executor.mli**

Append to `lib/executor.mli` after the existing `val to_curl` line:

```ocaml
val run : curl_invocation -> (string, string) result Async.Deferred.t
(** Spawn curl with the given invocation and return combined stdout, or an error string. *)
```

- [ ] **Step 3: Implement run in executor.ml**

Add at the bottom of `lib/executor.ml`:

```ocaml
open Async

let run invocation =
  match%map
    Process.run ~prog:"curl" ~args:invocation.args ()
  with
  | Ok stdout -> Ok stdout
  | Error err -> Error (Error.to_string_hum err)
```

- [ ] **Step 4: Build**

```
opam exec --switch freight-vcaml -- dune build lib/ 2>&1
```

Expected: clean build

- [ ] **Step 5: Commit**

```
jj describe -m "feat(executor): add run to spawn curl and capture output"
jj new
```

---

### Task 2: Add `render_response` to request_view

`Freight.Response.render` returns `string list`. We need a thin wrapper in `bin/request_view.ml` that names the buffer and produces lines for Scratch.show.

**Files:**

- Modify: `bin/request_view.ml`

- [ ] **Step 1: Append render_response to request_view.ml**

```ocaml
let render_response response =
  Freight.Response.render response
```

That's it — `Response.render` already produces a ready list of lines with status, headers, blank line, pretty-printed body.

- [ ] **Step 2: Build**

```
opam exec --switch freight-vcaml -- dune build bin/ 2>&1
```

Expected: clean

- [ ] **Step 3: Commit**

```
jj describe -m "feat(request_view): add render_response wrapper"
jj new
```

---

### Task 3: Wire freight_run to execute curl

`freight_run` currently calls `to_curl` and shows the inspect view. Change it to actually run curl, parse the output, and show the response. Move the old inspect body into `freight_inspect` (which is the `:FreightInspect` handler).

**Files:**

- Modify: `bin/handlers.ml`

Current `freight_run` (for reference — read the file to confirm line numbers):

```ocaml
let freight_run ~rpc state =
  let%bind buf, lines = get_current_buf_lines rpc in
  let source = String.concat lines ~sep:"\n" in
  match Freight.Parser.parse_string source with
  | Error err ->
    Scratch.show ~rpc ~name:"freight://error" ~filetype:"text"
      ~lines:(Request_view.render_parse_error err)
  | Ok file ->
    (match Freight.Parser.request_at_cursor file.Freight.Ast.requests 0 with
     | None -> show_error ~rpc "No requests found in buffer."
     | Some request ->
       let%bind dir_opt = get_buf_path rpc buf in
       let env =
         match dir_opt with
         | Some dir -> Freight.Env.load ~dir ~active_env:state.State.active_env
         | None -> state.State.env
       in
       let request =
         { request with
           Freight.Ast.url = Freight.Env.substitute env request.Freight.Ast.url
         ; headers =
             List.map request.Freight.Ast.headers ~f:(fun (k, v) ->
               (k, Freight.Env.substitute env v))
         }
       in
       let invocation = Freight.Executor.to_curl request in
       Scratch.show ~rpc ~name:"freight://inspect" ~filetype:"text"
         ~lines:(Request_view.render_request request invocation))
```

Current `freight_inspect` just shows a stub message. Replace both.

- [ ] **Step 1: Replace freight_inspect and freight_run in handlers.ml**

The full new `freight_inspect` and `freight_run` (replace from `let freight_inspect` through end of `let freight_run`):

```ocaml
let resolve_request ~rpc state =
  let%bind buf, lines = get_current_buf_lines rpc in
  let source = String.concat lines ~sep:"\n" in
  match Freight.Parser.parse_string source with
  | Error err -> return (Error (`Parse err))
  | Ok file ->
    (match Freight.Parser.request_at_cursor file.Freight.Ast.requests 0 with
     | None -> return (Error `No_request)
     | Some request ->
       let%bind dir_opt = get_buf_path rpc buf in
       let env =
         match dir_opt with
         | Some dir -> Freight.Env.load ~dir ~active_env:state.State.active_env
         | None -> state.State.env
       in
       let request =
         { request with
           Freight.Ast.url = Freight.Env.substitute env request.Freight.Ast.url
         ; headers =
             List.map request.Freight.Ast.headers ~f:(fun (k, v) ->
               (k, Freight.Env.substitute env v))
         }
       in
       return (Ok request))

let freight_inspect ~rpc state =
  match%bind resolve_request ~rpc state with
  | Error (`Parse err) ->
    Scratch.show ~rpc ~name:"freight://error" ~filetype:"text"
      ~lines:(Request_view.render_parse_error err)
  | Error `No_request -> show_error ~rpc "No requests found in buffer."
  | Ok request ->
    let invocation = Freight.Executor.to_curl request in
    Scratch.show ~rpc ~name:"freight://inspect" ~filetype:"text"
      ~lines:(Request_view.render_request request invocation)

let freight_run ~rpc state =
  match%bind resolve_request ~rpc state with
  | Error (`Parse err) ->
    Scratch.show ~rpc ~name:"freight://error" ~filetype:"text"
      ~lines:(Request_view.render_parse_error err)
  | Error `No_request -> show_error ~rpc "No requests found in buffer."
  | Ok request ->
    let invocation = Freight.Executor.to_curl request in
    (match%bind Freight.Executor.run invocation with
     | Error msg -> show_error ~rpc (Printf.sprintf "curl failed: %s" msg)
     | Ok raw ->
       (match Freight.Response.parse_curl_output raw request with
        | Error msg -> show_error ~rpc (Printf.sprintf "parse error: %s" msg)
        | Ok response ->
          Scratch.show ~rpc ~name:"freight://response" ~filetype:"text"
            ~lines:(Request_view.render_response response)))
```

- [ ] **Step 2: Build**

```
opam exec --switch freight-vcaml -- dune build bin/main.exe 2>&1
```

Expected: clean

- [ ] **Step 3: Commit**

```
jj describe -m "feat(handlers): freight_run executes curl and shows response"
jj new
```

---

### Task 4: Fix buffer name collision

When the same named buffer already exists (e.g. `freight://response` from a previous run), `nvim_buf_set_name` fails with `E95: Buffer with this name already exists`. Fix `Scratch.show` to reuse an existing buffer by that name instead of always creating a new one.

**Files:**

- Modify: `bin/scratch.ml`

The fix: call `nvim_buf_get_number` with the name to check, or simpler — after `nvim_create_buf`, try `nvim_buf_set_name` and if it fails with E95, find the existing buffer by name and wipe it first with `nvim_command "bwipeout freight://..."`.

Simplest correct approach: delete-then-set. Before setting the name on a new buffer, issue `silent! bwipeout <name>` to remove any existing buffer with that name.

- [ ] **Step 1: Update show in scratch.ml**

Replace `let show ~rpc ~name ~filetype ~lines =` with:

```ocaml
let show ~rpc ~name ~filetype ~lines =
  let%bind buf = nvim_call rpc "nvim_create_buf" [ Msgpck.Bool false; Msgpck.Bool true ] in
  let handle_int = match buf with
    | Msgpck.Int n -> n
    | Msgpck.Ext (_, s) -> ext_to_int s
    | _ -> failwith "expected buffer handle"
  in
  (* Wipe any existing buffer with this name before claiming it *)
  let%bind _ = nvim_call rpc "nvim_command"
    [ Msgpck.String (Printf.sprintf "silent! bwipeout %s" name) ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_name" [ buf; Msgpck.String name ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "buftype"; Msgpck.String "nofile" ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "filetype"; Msgpck.String filetype ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "modifiable"; Msgpck.Bool true ] in
  let flat_lines = List.concat_map lines ~f:(String.split ~on:'\n') in
  let msgpack_lines = Msgpck.List (List.map flat_lines ~f:(fun l -> Msgpck.String l)) in
  let%bind _ = nvim_call rpc "nvim_buf_set_lines" [ buf; Msgpck.Int 0; Msgpck.Int (-1); Msgpck.Bool false; msgpack_lines ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "modifiable"; Msgpck.Bool false ] in
  let%map _ = nvim_call rpc "nvim_command" [ Msgpck.String (Printf.sprintf "split | buffer %d" handle_int) ] in
  ()
```

- [ ] **Step 2: Build**

```
opam exec --switch freight-vcaml -- dune build bin/main.exe 2>&1
```

Expected: clean

- [ ] **Step 3: Commit**

```
jj describe -m "fix(scratch): wipe existing named buffer before reuse to avoid E95"
jj new
```

---

### Task 5: Smoke test

Rebuild, reload Neovim, verify the full flow.

**Files:** none

- [ ] **Step 1: Build the binary**

```
opam exec --switch freight-vcaml -- dune build bin/main.exe 2>&1
```

Expected: no output

- [ ] **Step 2: Restart Neovim**

Quit and reopen. Or run `:FreightStart` if available. Open `scratch.http`.

- [ ] **Step 3: Run FreightRun**

Place cursor on a request and run `:FreightRun`.

Expected: a `freight://response` split opens showing something like:
```
HTTP 200 OK (342 ms)
Content-Type: application/json
...

{
  "url": "https://httpbin.org/get",
  ...
}
```

- [ ] **Step 4: Run FreightInspect**

Run `:FreightInspect`.

Expected: `freight://inspect` split opens showing curl args (same as old `:FreightRun` behaviour).

- [ ] **Step 5: Run FreightRun again on same request**

Expected: no E95 error — buffer refreshes cleanly.

- [ ] **Step 6: Commit**

```
jj describe -m "test(smoke): FreightRun executes curl and FreightInspect shows args"
jj new
```
