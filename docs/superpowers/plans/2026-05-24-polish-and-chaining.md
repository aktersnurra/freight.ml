# Polish and Chaining Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three improvements: (1) response buffers open with the correct filetype for syntax highlighting; (2) `:FreightRun` shows a loading indicator while curl runs instead of blocking silently; (3) after each run, response values are injected into the env so subsequent requests can reference `{{name.response.body.field}}` and `{{name.response.headers.content-type}}`.

**Architecture:** The library already has `Buffer.filetype_of_content_type`, `Buffer.buffer_name`, and `Chaining.inject` — these just need wiring in `bin/handlers.ml` and `bin/scratch.ml`. For async loading: open a placeholder buffer immediately, `don't_wait_for` the curl execution, then update the buffer in place when done using a new `Scratch.update` function that writes to an existing buffer handle without opening a new split.

**Tech Stack:** OCaml, Async (already in use), existing Freight library modules.

---

## File structure

- Modify: `bin/handlers.ml` — use `Freight.Buffer.buffer_name` and `filetype_of_content_type` for response buffer; call `Chaining.inject` after each successful run to update `state.env`; restructure `freight_run` for async loading pattern
- Modify: `bin/scratch.ml` — add `update` function that writes lines to an existing buffer (by handle) without opening a split; add `show_loading` that opens the split immediately with a placeholder
- Modify: `bin/state.ml` and `bin/state.mli` — no changes needed, `state.env` is already mutable

---

### Task 1: Correct filetype and buffer name for responses

Wire `Freight.Buffer` into the response display path. Currently `freight_run` hardcodes `~name:"freight://response"` and `~filetype:"text"`.

**Files:**

- Modify: `bin/handlers.ml`

Current `freight_run` tail (the `Ok response ->` branch):

```ocaml
| Ok response ->
  Scratch.show ~rpc ~name:"freight://response" ~filetype:"text"
    ~lines:(Freight.Response.render response)
```

- [ ] **Step 1: Replace hardcoded name/filetype with Buffer module**

Change that branch to:

```ocaml
| Ok response ->
  let name = Freight.Buffer.buffer_name request in
  let filetype =
    Freight.Buffer.filetype_of_content_type
      (Freight.Response.detect_content_type response)
  in
  Scratch.show ~rpc ~name ~filetype
    ~lines:(Freight.Response.render response)
```

- [ ] **Step 2: Build**

```
opam exec --switch freight-vcaml -- dune build bin/main.exe 2>&1
```

Expected: clean

- [ ] **Step 3: Smoke test**

Restart Neovim. Run `:FreightRun` on a JSON endpoint (e.g. `GET https://httpbin.org/get`).

Expected: the response buffer opens with `filetype=json` — JSON body is syntax-highlighted.

- [ ] **Step 4: Commit**

```
jj describe -m "feat(handlers): use Buffer module for response buffer name and filetype"
jj new
```

---

### Task 2: Request chaining — inject response into env

After a successful run, call `Chaining.inject` to merge the response's body fields and headers into `state.env`. This enables subsequent requests to use `{{name.response.body.token}}` or `{{name.response.headers.x-request-id}}` via the existing `Env.substitute` path.

`Chaining.inject ~name response env` requires a `name` — use the request's `name` field if present, fall back to an empty string (env keys would just be `.response.body.field`, which is unusual but harmless).

**Files:**

- Modify: `bin/handlers.ml`
- Modify: `bin/dune` — add `freight`'s `chaining` module (it's in the same `freight` library, no dune change needed since `freight` is already a dep)

- [ ] **Step 1: Inject response into state.env in freight_run**

After the `Ok response ->` branch (after `Scratch.show`), add the injection. Since `Scratch.show` returns `unit Deferred.t`, use `let%map`:

Replace the full `Ok response ->` branch with:

```ocaml
| Ok response ->
  let name = Freight.Buffer.buffer_name request in
  let filetype =
    Freight.Buffer.filetype_of_content_type
      (Freight.Response.detect_content_type response)
  in
  let req_name = Option.value request.Freight.Ast.name ~default:"" in
  state.State.env <- Freight.Chaining.inject ~name:req_name response state.State.env;
  Scratch.show ~rpc ~name ~filetype
    ~lines:(Freight.Response.render response)
```

- [ ] **Step 2: Build**

```
opam exec --switch freight-vcaml -- dune build bin/main.exe 2>&1
```

Expected: clean

- [ ] **Step 3: Test chaining manually**

Create a file:

```http
# @name login
POST https://httpbin.org/post
Content-Type: application/json

{"token": "abc123"}

###

# @name use_token
GET https://httpbin.org/headers
X-Token: {{login.response.body.json}}
```

Run `:FreightRun` on `login`, then move cursor to `use_token` and run `:FreightRun` again.

Expected: the second request's `X-Token` header is substituted with the value extracted from the first response.

Note: httpbin.org's `/post` endpoint nests the JSON body under a `json` key, so the path is `login.response.body.json` (an object, not a scalar — it won't substitute, but headers like `Content-Type` will). For a real chain test, use an endpoint that returns scalar top-level fields.

- [ ] **Step 4: Commit**

```
jj describe -m "feat(handlers): inject response into env after each run for request chaining"
jj new
```

---

### Task 3: Async loading — show placeholder while curl runs

Currently `:FreightRun` blocks Neovim while curl executes. Fix: open the buffer immediately with a "Loading…" placeholder, then update it in place when the response arrives. The Async scheduler already runs the event loop — we just need `don't_wait_for` around the curl+update work.

This requires a new `Scratch.update` function that writes new lines to an existing buffer handle (already opened in a split) without creating a new split.

**Files:**

- Modify: `bin/scratch.ml` — add `update`
- Modify: `bin/handlers.ml` — restructure `freight_run` to open loading buffer then `don't_wait_for` the rest

**Step 1: Add `Scratch.update`**

`update` takes a buffer handle (the `Msgpck.t` value returned by `nvim_create_buf`) and new lines, and writes them to the buffer. It does NOT open a split — the buffer is already visible.

- [ ] **Step 1a: Add `update` to scratch.ml**

Append to `bin/scratch.ml`:

```ocaml
let update ~rpc buf ~filetype ~lines =
  let flat_lines = List.concat_map lines ~f:(String.split ~on:'\n') in
  let msgpack_lines = Msgpck.List (List.map flat_lines ~f:(fun l -> Msgpck.String l)) in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "modifiable"; Msgpck.Bool true ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "filetype"; Msgpck.String filetype ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_lines" [ buf; Msgpck.Int 0; Msgpck.Int (-1); Msgpck.Bool false; msgpack_lines ] in
  let%map _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "modifiable"; Msgpck.Bool false ] in
  ()
```

- [ ] **Step 1b: Add `show_and_return_handle` to scratch.ml**

We need `show` to return the buffer handle so the caller can pass it to `update`. Add a variant that returns `Msgpck.t`:

```ocaml
let show_loading ~rpc ~name =
  let%bind buf = nvim_call rpc "nvim_create_buf" [ Msgpck.Bool false; Msgpck.Bool true ] in
  let handle_int = match buf with
    | Msgpck.Int n -> n
    | Msgpck.Ext (_, s) -> ext_to_int s
    | _ -> failwith "expected buffer handle"
  in
  let%bind _ = nvim_call rpc "nvim_command"
    [ Msgpck.String (Printf.sprintf "silent! bwipeout %s" name) ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_name" [ buf; Msgpck.String name ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "buftype"; Msgpck.String "nofile" ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "modifiable"; Msgpck.Bool true ] in
  let loading = Msgpck.List [ Msgpck.String "Loading…" ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_lines" [ buf; Msgpck.Int 0; Msgpck.Int (-1); Msgpck.Bool false; loading ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "modifiable"; Msgpck.Bool false ] in
  let%map _ = nvim_call rpc "nvim_command" [ Msgpck.String (Printf.sprintf "split | buffer %d" handle_int) ] in
  buf
```

- [ ] **Step 2: Restructure freight_run for async loading**

Replace the `freight_run` function body from the `| Some request ->` branch onward:

```ocaml
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
    let name = Freight.Buffer.buffer_name request in
    let%map loading_buf = Scratch.show_loading ~rpc ~name in
    don't_wait_for begin
      match%bind Freight.Executor.run invocation with
      | Error msg ->
        Scratch.update ~rpc loading_buf ~filetype:"text"
          ~lines:[ "Error: " ^ msg ]
      | Ok raw ->
        match Freight.Response.parse_curl_output raw request with
        | Error msg ->
          Scratch.update ~rpc loading_buf ~filetype:"text"
            ~lines:[ "Parse error: " ^ msg ]
        | Ok response ->
          let filetype =
            Freight.Buffer.filetype_of_content_type
              (Freight.Response.detect_content_type response)
          in
          let req_name = Option.value request.Freight.Ast.name ~default:"" in
          state.State.env <- Freight.Chaining.inject ~name:req_name response state.State.env;
          Scratch.update ~rpc loading_buf ~filetype
            ~lines:(Freight.Response.render response)
    end
```

Note: this also supersedes Task 1 and Task 2 — the filetype and chaining wiring is included here. If Tasks 1 and 2 were already committed, those changes will be overwritten by this step — that is fine.

- [ ] **Step 3: Build**

```
opam exec --switch freight-vcaml -- dune build bin/main.exe 2>&1
```

Expected: clean

- [ ] **Step 4: Smoke test**

Restart Neovim. Run `:FreightRun` on a slow endpoint or any request.

Expected:
- The `freight://response/...` split opens immediately with "Loading…"
- Within a second or two (network permitting) it updates in place with the actual response
- Neovim is not frozen while curl runs

- [ ] **Step 5: Commit**

```
jj describe -m "feat(run): async loading buffer; correct filetype; request chaining"
jj new
```
