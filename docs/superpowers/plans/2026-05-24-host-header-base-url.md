# Host Header Base URL Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Support `Host: {{url}}` as a base URL shorthand, so requests with a relative path (e.g. `POST /post`) automatically get the host prepended after env substitution.

**Architecture:** Add a pure `apply_host_header` function to `lib/ast.ml` that takes a post-substitution request and, if the URL is a relative path and a `Host` header is present, prepends the host value to the URL and removes the `Host` header. Wire this into a shared `resolve_request` helper in `bin/handlers.ml` that replaces the duplicated substitution blocks in `freight_inspect` and `freight_run`.

**Tech Stack:** OCaml, OUnit2 tests, existing Freight library + bin layer.

---

## File structure

- Modify: `lib/ast.mli` — add `val apply_host_header : request -> request`
- Modify: `lib/ast.ml` — implement `apply_host_header`
- Modify: `test/test_freight.ml` — add tests for `apply_host_header`
- Modify: `bin/handlers.ml` — extract `resolve_request` helper; call `apply_host_header` after substitution; replace duplicated substitution blocks in `freight_inspect` and `freight_run`

---

### Task 1: Add `apply_host_header` to Ast

**Files:**

- Modify: `lib/ast.mli`
- Modify: `lib/ast.ml`
- Modify: `test/test_freight.ml`

The function inspects a (already-substituted) request. If `url` starts with `/` AND a `Host` header exists (case-insensitive match on `"host"`), it prepends the host value to the url and removes the `Host` header from the list.

If the url is not relative, or no `Host` header exists, the request is returned unchanged.

The host value should be trimmed of a trailing `/` before prepending, so `https://api.example.com/` + `/users` doesn't produce `https://api.example.com//users`.

- [ ] **Step 1: Write failing tests**

Read `test/test_freight.ml` to find the right place to insert (near other ast/parser tests). Add these tests:

```ocaml
let test_apply_host_header_relative_url _ =
  let request = {
    Freight.Ast.name = None;
    method_ = Freight.Ast.Post;
    url = "/post";
    headers = [ ("Host", "https://httpbin.org"); ("Content-Type", "application/json") ];
    body = Freight.Ast.Body_none;
  } in
  let result = Freight.Ast.apply_host_header request in
  assert_equal "https://httpbin.org/post" result.Freight.Ast.url;
  assert_equal [ ("Content-Type", "application/json") ] result.Freight.Ast.headers

let test_apply_host_header_trailing_slash _ =
  let request = {
    Freight.Ast.name = None;
    method_ = Freight.Ast.Get;
    url = "/users";
    headers = [ ("Host", "https://api.example.com/") ];
    body = Freight.Ast.Body_none;
  } in
  let result = Freight.Ast.apply_host_header request in
  assert_equal "https://api.example.com/users" result.Freight.Ast.url;
  assert_equal [] result.Freight.Ast.headers

let test_apply_host_header_absolute_url_unchanged _ =
  let request = {
    Freight.Ast.name = None;
    method_ = Freight.Ast.Get;
    url = "https://httpbin.org/get";
    headers = [ ("Host", "https://other.example.com") ];
    body = Freight.Ast.Body_none;
  } in
  let result = Freight.Ast.apply_host_header request in
  assert_equal "https://httpbin.org/get" result.Freight.Ast.url;
  assert_equal [ ("Host", "https://other.example.com") ] result.Freight.Ast.headers

let test_apply_host_header_no_host_unchanged _ =
  let request = {
    Freight.Ast.name = None;
    method_ = Freight.Ast.Get;
    url = "/users";
    headers = [ ("Content-Type", "application/json") ];
    body = Freight.Ast.Body_none;
  } in
  let result = Freight.Ast.apply_host_header request in
  assert_equal "/users" result.Freight.Ast.url;
  assert_equal [ ("Content-Type", "application/json") ] result.Freight.Ast.headers

let test_apply_host_header_case_insensitive _ =
  let request = {
    Freight.Ast.name = None;
    method_ = Freight.Ast.Get;
    url = "/ping";
    headers = [ ("HOST", "https://api.example.com") ];
    body = Freight.Ast.Body_none;
  } in
  let result = Freight.Ast.apply_host_header request in
  assert_equal "https://api.example.com/ping" result.Freight.Ast.url;
  assert_equal [] result.Freight.Ast.headers
```

Register all five in the test suite (find the suite list — look for `>:: test_` entries — and add):

```ocaml
"apply_host_header_relative_url" >:: test_apply_host_header_relative_url;
"apply_host_header_trailing_slash" >:: test_apply_host_header_trailing_slash;
"apply_host_header_absolute_url_unchanged" >:: test_apply_host_header_absolute_url_unchanged;
"apply_host_header_no_host_unchanged" >:: test_apply_host_header_no_host_unchanged;
"apply_host_header_case_insensitive" >:: test_apply_host_header_case_insensitive;
```

- [ ] **Step 2: Run tests to verify they fail**

```
opam exec --switch freight-vcaml -- dune test test/test_freight.exe 2>&1 | tail -5
```

Expected: FAIL — `Unbound value Freight.Ast.apply_host_header`

- [ ] **Step 3: Add val to ast.mli**

Append to `lib/ast.mli` after `val method_of_string`:

```ocaml
val apply_host_header : request -> request
(** If [request.url] is a relative path (starts with [/]) and a [Host] header
    is present, prepends the host value to the url and removes the [Host]
    header. Returns the request unchanged otherwise. *)
```

- [ ] **Step 4: Implement in ast.ml**

Append to `lib/ast.ml` after `method_of_string`:

```ocaml
let apply_host_header request =
  if not (String.length request.url > 0 && request.url.[0] = '/') then request
  else
    match
      List.partition
        (fun (k, _) -> String.equal (String.lowercase_ascii k) "host")
        request.headers
    with
    | [], _ -> request
    | (_, host_value) :: _, rest_headers ->
      let host = String.trim host_value in
      let base =
        if String.length host > 0 && host.[String.length host - 1] = '/' then
          String.sub host 0 (String.length host - 1)
        else host
      in
      { request with url = base ^ request.url; headers = rest_headers }
```

- [ ] **Step 5: Run tests to verify they pass**

```
opam exec --switch freight-vcaml -- dune test test/test_freight.exe 2>&1 | tail -5
```

Expected: all tests pass, count increases by 5.

- [ ] **Step 6: Commit**

```
jj describe -m "feat(ast): apply_host_header prepends Host value to relative URL paths"
jj new
```

---

### Task 2: Wire into handlers via resolve_request helper

The substitution block is duplicated identically in `freight_inspect` and `freight_run`. Extract it into a local `resolve_request` helper and call `apply_host_header` inside it.

**Files:**

- Modify: `bin/handlers.ml`

Current duplicated block (appears twice — once in `freight_inspect`, once in `freight_run`):

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
```

- [ ] **Step 1: Add resolve_request helper before freight_inspect**

Insert this function between `freight_env` and `freight_inspect` in `bin/handlers.ml`:

```ocaml
let resolve_request ~rpc state source cursor_line buf =
  match Freight.Parser.request_at_cursor source cursor_line with
  | None ->
    (match Freight.Parser.parse_string source with
     | Error err -> return (Error (`Parse err))
     | Ok _ -> return (Error `No_request))
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
    return (Ok (Freight.Ast.apply_host_header request))
```

- [ ] **Step 2: Replace freight_inspect body**

Replace the entire `freight_inspect` function with:

```ocaml
let freight_inspect ~rpc state =
  let%bind buf, lines, cursor_line = get_current_buf_lines rpc in
  let source = String.concat lines ~sep:"\n" in
  match%bind resolve_request ~rpc state source cursor_line buf with
  | Error (`Parse err) ->
    Scratch.show ~rpc ~name:"freight://error" ~filetype:"text"
      ~lines:(Request_view.render_parse_error err)
  | Error `No_request -> show_error ~rpc "No requests found in buffer."
  | Ok request ->
    let invocation = Freight.Executor.to_curl request in
    Scratch.show ~rpc ~name:"freight://inspect" ~filetype:"text"
      ~lines:(Request_view.render_request request invocation)
```

- [ ] **Step 3: Replace freight_run body**

Replace the entire `freight_run` function with:

```ocaml
let freight_run ~rpc state =
  let%bind buf, lines, cursor_line = get_current_buf_lines rpc in
  let source = String.concat lines ~sep:"\n" in
  match%bind resolve_request ~rpc state source cursor_line buf with
  | Error (`Parse err) ->
    Scratch.show ~rpc ~name:"freight://error" ~filetype:"text"
      ~lines:(Request_view.render_parse_error err)
  | Error `No_request -> show_error ~rpc "No requests found in buffer."
  | Ok request ->
    let invocation = Freight.Executor.to_curl request in
    let name = Freight.Buffer.buffer_name request in
    let%map loading_buf = Scratch.show_loading ~rpc ~name in
    don't_wait_for begin
      match%bind
        Monitor.try_with (fun () ->
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
                ~lines:(Freight.Response.render response))
      with
      | Ok () -> return ()
      | Error exn ->
        (match%map
           Monitor.try_with (fun () ->
             Scratch.update ~rpc loading_buf ~filetype:"text"
               ~lines:[ "Internal error: " ^ Exn.to_string exn ])
         with
         | Ok () | Error _ -> ())
    end
```

- [ ] **Step 4: Build**

```
opam exec --switch freight-vcaml -- dune build bin/main.exe 2>&1
```

Expected: clean.

- [ ] **Step 5: Smoke test**

Restart Neovim. Create a file:

```http
# @name post_json
POST /post
Host: {{url}}
Content-Type: application/json

{"message": "{{message}}"}
```

With `.env`:
```
url=https://httpbin.org
message=hello from freight
```

Run `:FreightRun`. Expected: request goes to `https://httpbin.org/post`, `Host` header not sent to curl, response shows the httpbin POST echo.

Run `:FreightInspect`. Expected: URL shows `https://httpbin.org/post`, no `Host` in headers list.

- [ ] **Step 6: Commit**

```
jj describe -m "feat(handlers): resolve_request helper applies host header and deduplicates substitution"
jj new
```
