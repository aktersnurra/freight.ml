# Core Library First Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure OCaml core library for freight.ml without VCaml, Async, or Core dependencies in `lib/`.

**Architecture:** Implement explicit `.mli` boundaries first, then test-driven module implementations. Keep process execution and Neovim UI integration out of this milestone; `Executor` only builds curl invocations and `Buffer` only computes pure names/filetypes.

**Tech Stack:** OCaml, dune, Angstrom, Yojson, Re, OUnit2 tests, jj.

---

## File structure

- Modify: `dune-project` — package metadata and dependencies.
- Modify: `lib/dune` — library dependency list and warning flags.
- Modify: `test/dune` — OUnit2 test executable dependencies.
- Create: `lib/ast.mli`, `lib/ast.ml` — shared request/response/domain types and method conversion helpers.
- Create: `lib/parser.mli`, `lib/parser.ml` — Angstrom `.http` parser and cursor lookup support.
- Create: `lib/env.mli`, `lib/env.ml` — `.env` loading, merge precedence, variable substitution.
- Create: `lib/executor.mli`, `lib/executor.ml` — pure curl argument construction.
- Create: `lib/response.mli`, `lib/response.ml` — curl output parsing, content-type detection, pretty-printing, rendering.
- Create: `lib/chaining.mli`, `lib/chaining.ml` — simple JSON/header extraction and env injection.
- Create: `lib/buffer.mli`, `lib/buffer.ml` — response buffer names and content-type-to-filetype mapping.
- Replace: `test/test_freight.ml` — OUnit2 tests for all core modules.
- Modify: `bin/main.ml` — keep minimal placeholder compiling against library.

---

### Task 1: Project dependencies and test harness

**Files:**

- Modify: `dune-project`
- Modify: `lib/dune`
- Modify: `test/dune`
- Replace: `test/test_freight.ml`

- [ ] **Step 1: Write the initial failing smoke test**

Replace `test/test_freight.ml` with:

```ocaml
open OUnit2

let test_method_to_string _ =
  assert_equal "GET" (Freight.Ast.method_to_string Freight.Ast.Get)

let suite =
  "freight" >::: [ "method_to_string" >:: test_method_to_string ]

let () = run_test_tt_main suite
```

- [ ] **Step 2: Update test dune stanza**

Replace `test/dune` with:

```lisp
(test
 (name test_freight)
 (libraries freight ounit2))
```

- [ ] **Step 3: Update library dependencies**

Replace `lib/dune` with:

```lisp
(library
 (name freight)
 (libraries angstrom yojson re)
 (flags (:standard -w @A-4-33-40-41-42-43-34-44)))
```

- [ ] **Step 4: Update package metadata**

Edit the `(package ...)` stanza in `dune-project` so it contains:

```lisp
(package
 (name freight)
 (synopsis "Neovim HTTP client plugin core library")
 (description "Core OCaml library for parsing, executing, and rendering HTTP requests for freight.ml")
 (depends
  ocaml
  dune
  angstrom
  yojson
  re
  ounit2)
 (tags
  (neovim http ocaml)))
```

Also update source metadata to:

```lisp
(source
 (github aktersnurra/freight.ml))
```

- [ ] **Step 5: Run the smoke test and verify it fails**

Run:

```bash
dune runtest
```

Expected: FAIL because `Freight.Ast.method_to_string` is not defined yet.

- [ ] **Step 6: Commit the harness change**

Run:

```bash
jj describe -m "build: configure core library test harness"
jj new
```

---

### Task 2: `Ast` types and helpers

**Files:**

- Create: `lib/ast.mli`
- Create: `lib/ast.ml`
- Modify: `test/test_freight.ml`

- [ ] **Step 1: Extend tests for method conversion**

Add these tests to `test/test_freight.ml`:

```ocaml
let test_method_of_string _ =
  assert_equal Freight.Ast.Post (Freight.Ast.method_of_string "POST");
  assert_equal (Freight.Ast.Custom "PROPFIND") (Freight.Ast.method_of_string "PROPFIND")
```

Add `"method_of_string" >:: test_method_of_string` to the suite list.

- [ ] **Step 2: Create `lib/ast.mli`**

```ocaml
type method_ =
  | Get
  | Post
  | Put
  | Patch
  | Delete
  | Head
  | Options
  | Trace
  | Connect
  | Custom of string

type body =
  | Body_inline of string
  | Body_file of string
  | Body_none

type request = {
  name : string option;
  method_ : method_;
  url : string;
  headers : (string * string) list;
  body : body;
}

type response = {
  status : int;
  status_text : string;
  headers : (string * string) list;
  body : string;
  duration_ms : int;
  request : request;
}

type parse_error = {
  message : string;
  line : int;
  snippet : string;
}

type http_file = {
  requests : request list;
  path : string;
}

val method_to_string : method_ -> string
val method_of_string : string -> method_
```

- [ ] **Step 3: Create `lib/ast.ml`**

```ocaml
type method_ =
  | Get
  | Post
  | Put
  | Patch
  | Delete
  | Head
  | Options
  | Trace
  | Connect
  | Custom of string

type body =
  | Body_inline of string
  | Body_file of string
  | Body_none

type request = {
  name : string option;
  method_ : method_;
  url : string;
  headers : (string * string) list;
  body : body;
}

type response = {
  status : int;
  status_text : string;
  headers : (string * string) list;
  body : string;
  duration_ms : int;
  request : request;
}

type parse_error = {
  message : string;
  line : int;
  snippet : string;
}

type http_file = {
  requests : request list;
  path : string;
}

let method_to_string = function
  | Get -> "GET"
  | Post -> "POST"
  | Put -> "PUT"
  | Patch -> "PATCH"
  | Delete -> "DELETE"
  | Head -> "HEAD"
  | Options -> "OPTIONS"
  | Trace -> "TRACE"
  | Connect -> "CONNECT"
  | Custom method_ -> method_

let method_of_string method_ =
  match String.uppercase_ascii method_ with
  | "GET" -> Get
  | "POST" -> Post
  | "PUT" -> Put
  | "PATCH" -> Patch
  | "DELETE" -> Delete
  | "HEAD" -> Head
  | "OPTIONS" -> Options
  | "TRACE" -> Trace
  | "CONNECT" -> Connect
  | custom -> Custom custom
```

- [ ] **Step 4: Run tests**

Run:

```bash
dune runtest
```

Expected: PASS for method helper tests.

- [ ] **Step 5: Commit**

Run:

```bash
jj describe -m "feat(ast): add core HTTP domain types"
jj new
```

---

### Task 3: Parser

**Files:**

- Create: `lib/parser.mli`
- Create: `lib/parser.ml`
- Modify: `test/test_freight.ml`

- [ ] **Step 1: Add parser tests**

Append tests that assert:

```ocaml
let parse_ok source =
  match Freight.Parser.parse_string source with
  | Ok file -> file
  | Error error -> assert_failure error.Freight.Ast.message

let test_parse_named_json_request _ =
  let file =
    parse_ok "# @name login\nPOST https://api.example.com/auth\nContent-Type: application/json\n\n{\"user\":\"me\"}\n"
  in
  match file.requests with
  | [ request ] ->
      assert_equal (Some "login") request.name;
      assert_equal Freight.Ast.Post request.method_;
      assert_equal "https://api.example.com/auth" request.url;
      assert_equal [ ("Content-Type", "application/json") ] request.headers;
      assert_equal (Freight.Ast.Body_inline "{\"user\":\"me\"}") request.body
  | _ -> assert_failure "expected one request"

let test_parse_two_requests_with_separator _ =
  let file = parse_ok "GET https://one.test\n\n###\nGET https://two.test\n\n" in
  assert_equal 2 (List.length file.requests)

let test_parse_body_file _ =
  let file = parse_ok "PUT https://api.example.com/upload\n\n< fixtures/payload.json\n" in
  match file.requests with
  | [ request ] -> assert_equal (Freight.Ast.Body_file "fixtures/payload.json") request.body
  | _ -> assert_failure "expected one request"
```

Add each test to the suite.

- [ ] **Step 2: Create `lib/parser.mli`**

```ocaml
val parse_string : string -> (Ast.http_file, Ast.parse_error) result
val parse_file : string -> (Ast.http_file, Ast.parse_error) result
val request_at_cursor : Ast.request list -> int -> Ast.request option
```

- [ ] **Step 3: Implement parser**

Create `lib/parser.ml` with an Angstrom-based parser. Use helper functions for trimming, splitting request blocks on lines whose trimmed text starts with `###`, parsing `# @name`, parsing the request line, headers until the first blank line, and parsing the remaining body.

Implementation constraints:

```ocaml
let request_at_cursor requests cursor_line =
  ignore cursor_line;
  match requests with
  | [] -> None
  | request :: _ -> Some request
```

This intentionally conservative implementation satisfies the current public type without adding line metadata to `Ast.request`; a later VCaml milestone can replace it with a ranged parse API.

- [ ] **Step 4: Run parser tests**

Run:

```bash
dune runtest
```

Expected: PASS including parser tests.

- [ ] **Step 5: Commit**

Run:

```bash
jj describe -m "feat(parser): parse http request files"
jj new
```

---

### Task 4: Env loading and substitution

**Files:**

- Create: `lib/env.mli`
- Create: `lib/env.ml`
- Modify: `test/test_freight.ml`

- [ ] **Step 1: Add env tests**

Add tests that create temporary directories/files and assert:

```ocaml
let write_file path contents =
  let channel = open_out path in
  output_string channel contents;
  close_out channel

let test_env_substitute_unknown_preserved _ =
  let env = Freight.Env.of_list [ ("host", "example.com") ] in
  assert_equal "https://example.com/{{missing}}" (Freight.Env.substitute env "https://{{host}}/{{missing}}")

let test_env_load_precedence _ =
  let root = Filename.concat (Filename.get_temp_dir_name ()) "freight-env-test" in
  let nested = Filename.concat root "a/b" in
  Unix.mkdir root 0o755;
  Unix.mkdir (Filename.concat root "a") 0o755;
  Unix.mkdir nested 0o755;
  write_file (Filename.concat root ".env") "TOKEN=base\nHOST=base.test\n";
  write_file (Filename.concat root ".env.dev") "TOKEN=dev\n";
  write_file (Filename.concat root ".env.local") "HOST=local.test\n";
  let env = Freight.Env.load ~dir:nested ~active_env:(Some "dev") in
  assert_equal (Some "dev") (Freight.Env.find env "TOKEN");
  assert_equal (Some "local.test") (Freight.Env.find env "HOST")
```

Add `unix` to `test/dune` libraries because the test uses `Unix.mkdir`.

- [ ] **Step 2: Create `lib/env.mli`**

```ocaml
type t

val empty : t
val of_list : (string * string) list -> t
val find : t -> string -> string option
val add : t -> key:string -> data:string -> t
val load : dir:string -> active_env:string option -> t
val substitute : t -> string -> string
```

- [ ] **Step 3: Implement `lib/env.ml`**

Use `Map.Make(String)`. Parse `.env` lines as `KEY=VALUE`, ignore blank lines and lines beginning with `#`. Walk ancestors from root toward the starting directory so nearer files override farther ones through the prescribed merge order.

Use Re to replace `{{ key }}` and preserve unknown variables unchanged.

- [ ] **Step 4: Run env tests**

Run:

```bash
dune runtest
```

Expected: PASS including env tests.

- [ ] **Step 5: Commit**

Run:

```bash
jj describe -m "feat(env): load and substitute http variables"
jj new
```

---

### Task 5: Curl invocation construction

**Files:**

- Create: `lib/executor.mli`
- Create: `lib/executor.ml`
- Modify: `test/test_freight.ml`

- [ ] **Step 1: Add executor tests**

Add tests for curl args:

```ocaml
let sample_request body =
  {
    Freight.Ast.name = Some "login";
    method_ = Freight.Ast.Post;
    url = "https://api.example.com/auth";
    headers = [ ("Content-Type", "application/json") ];
    body;
  }

let test_to_curl_inline_body _ =
  let invocation = Freight.Executor.to_curl (sample_request (Freight.Ast.Body_inline "{}")) in
  assert_bool "has -i" (List.mem "-i" invocation.args);
  assert_bool "has -s" (List.mem "-s" invocation.args);
  assert_bool "has method" (List.mem "POST" invocation.args);
  assert_bool "has header" (List.mem "Content-Type: application/json" invocation.args);
  assert_bool "has data flag" (List.mem "--data-binary" invocation.args);
  assert_bool "has body" (List.mem "{}" invocation.args)

let test_to_curl_file_body _ =
  let invocation = Freight.Executor.to_curl (sample_request (Freight.Ast.Body_file "payload.json")) in
  assert_bool "has file upload" (List.mem "@payload.json" invocation.args)
```

- [ ] **Step 2: Create `lib/executor.mli`**

```ocaml
type curl_invocation = {
  args : string list;
  env : (string * string) list;
}

val to_curl : Ast.request -> curl_invocation
```

- [ ] **Step 3: Implement `lib/executor.ml`**

Build args with:

- `-i`
- `-s`
- `-X`, method string
- repeated `-H`, `Key: Value`
- body args when present
- URL positional arg
- `-w`, `\n%{http_code}\n%{time_total}`

For `Put` plus `Body_file p`, use `-T p`. For other file bodies, use `--data-binary @p`.

- [ ] **Step 4: Run executor tests**

Run:

```bash
dune runtest
```

Expected: PASS including executor tests.

- [ ] **Step 5: Commit**

Run:

```bash
jj describe -m "feat(executor): build curl invocations"
jj new
```

---

### Task 6: Response parsing and rendering

**Files:**

- Create: `lib/response.mli`
- Create: `lib/response.ml`
- Modify: `test/test_freight.ml`

- [ ] **Step 1: Add response tests**

Add tests:

```ocaml
let response_request =
  {
    Freight.Ast.name = Some "login";
    method_ = Freight.Ast.Get;
    url = "https://api.example.com";
    headers = [];
    body = Freight.Ast.Body_none;
  }

let test_parse_curl_output _ =
  let raw = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"token\":\"abc\"}\n200\n0.142" in
  match Freight.Response.parse_curl_output raw response_request with
  | Ok response ->
      assert_equal 200 response.status;
      assert_equal "OK" response.status_text;
      assert_equal 142 response.duration_ms;
      assert_equal "{\"token\":\"abc\"}" response.body
  | Error message -> assert_failure message

let test_pretty_print_json _ =
  assert_equal "{\n  \"token\": \"abc\"\n}" (Freight.Response.pretty_print_body Freight.Response.Json "{\"token\":\"abc\"}")
```

- [ ] **Step 2: Create `lib/response.mli`**

```ocaml
type content_type =
  | Json
  | Xml
  | Html
  | Plain
  | Other of string

val parse_curl_output : string -> Ast.request -> (Ast.response, string) result
val detect_content_type : Ast.response -> content_type
val pretty_print_body : content_type -> string -> string
val render : Ast.response -> string list
```

- [ ] **Step 3: Implement `lib/response.ml`**

Parse the final two lines as status code and time total. Parse the first HTTP header block before the first blank line. Compute `duration_ms` as `int_of_float (seconds *. 1000.)`. Use `Yojson.Safe.from_string` and `Yojson.Safe.pretty_to_string` for JSON, returning the original body if parsing fails.

- [ ] **Step 4: Run response tests**

Run:

```bash
dune runtest
```

Expected: PASS including response tests.

- [ ] **Step 5: Commit**

Run:

```bash
jj describe -m "feat(response): parse and render curl output"
jj new
```

---

### Task 7: Chaining

**Files:**

- Create: `lib/chaining.mli`
- Create: `lib/chaining.ml`
- Modify: `test/test_freight.ml`

- [ ] **Step 1: Add chaining tests**

Add tests:

```ocaml
let login_response =
  {
    Freight.Ast.status = 200;
    status_text = "OK";
    headers = [ ("X-Request-Id", "req-1") ];
    body = "{\"token\":\"abc\",\"user\":{\"id\":\"42\"}}";
    duration_ms = 10;
    request = response_request;
  }

let test_extract_body_path _ =
  assert_equal (Some "42") (Freight.Chaining.extract login_response (Freight.Chaining.Response_body [ "user"; "id" ]))

let test_extract_header _ =
  assert_equal (Some "req-1") (Freight.Chaining.extract login_response (Freight.Chaining.Response_header "X-Request-Id"))

let test_inject_named_response _ =
  let env = Freight.Chaining.inject ~name:"login" login_response Freight.Env.empty in
  assert_equal (Some "abc") (Freight.Env.find env "login.response.body.token");
  assert_equal (Some "req-1") (Freight.Env.find env "login.response.headers.X-Request-Id")
```

- [ ] **Step 2: Create `lib/chaining.mli`**

```ocaml
type extraction_path =
  | Response_body of string list
  | Response_header of string

val extract : Ast.response -> extraction_path -> string option
val inject : name:string -> Ast.response -> Env.t -> Env.t
```

- [ ] **Step 3: Implement `lib/chaining.ml`**

Use Yojson for body extraction. Support only JSON object key traversal. Convert scalar JSON values to strings. Header lookup should be case-insensitive for extraction, but injected keys should preserve the response header spelling.

- [ ] **Step 4: Run chaining tests**

Run:

```bash
dune runtest
```

Expected: PASS including chaining tests.

- [ ] **Step 5: Commit**

Run:

```bash
jj describe -m "feat(chaining): inject named response values"
jj new
```

---

### Task 8: Buffer helpers

**Files:**

- Create: `lib/buffer.mli`
- Create: `lib/buffer.ml`
- Modify: `test/test_freight.ml`

- [ ] **Step 1: Add buffer tests**

Add tests:

```ocaml
let test_named_buffer_name _ =
  assert_equal "freight://response/login" (Freight.Buffer.buffer_name response_request)

let test_slugged_buffer_name _ =
  let request = { response_request with name = None; method_ = Freight.Ast.Post; url = "https://api.example.com/data" } in
  assert_equal "freight://response/post-api-example-com-data" (Freight.Buffer.buffer_name request)

let test_filetype_mapping _ =
  assert_equal "json" (Freight.Buffer.filetype_of_content_type Freight.Response.Json);
  assert_equal "text" (Freight.Buffer.filetype_of_content_type Freight.Response.Plain)
```

- [ ] **Step 2: Create `lib/buffer.mli`**

```ocaml
val buffer_name : Ast.request -> string
val filetype_of_content_type : Response.content_type -> string
```

- [ ] **Step 3: Implement `lib/buffer.ml`**

Slug unnamed requests by lowercasing `method-url`, replacing non-alphanumeric runs with `-`, and trimming leading/trailing dashes.

- [ ] **Step 4: Run buffer tests**

Run:

```bash
dune runtest
```

Expected: PASS including buffer tests.

- [ ] **Step 5: Commit**

Run:

```bash
jj describe -m "feat(buffer): add pure response buffer helpers"
jj new
```

---

### Task 9: Final integration pass

**Files:**

- Modify: `bin/main.ml`
- Modify: `freight.opam` if dune does not regenerate it automatically

- [ ] **Step 1: Keep executable minimal**

Replace `bin/main.ml` with:

```ocaml
let () = print_endline "freight.ml core library installed"
```

- [ ] **Step 2: Run formatting if available**

Run:

```bash
which ocamlformat >/dev/null 2>&1 && ocamlformat -i lib/*.ml lib/*.mli test/*.ml bin/*.ml || true
```

Expected: command exits successfully whether or not `ocamlformat` is installed.

- [ ] **Step 3: Run full build and tests**

Run:

```bash
dune build && dune runtest
```

Expected: build succeeds and all tests pass.

- [ ] **Step 4: Inspect jj status**

Run:

```bash
jj st
```

Expected: only intentional source/test/metadata changes are present in the current change; `_build/` is ignored.

- [ ] **Step 5: Commit final integration**

Run:

```bash
jj describe -m "chore: finish core library milestone"
jj new
```

---

## Self-review

- Spec coverage: the plan covers the approved core-library-first scope: pure `lib/` modules, no VCaml/Async/Core in `lib/`, tests for parser/env/executor/response/chaining/buffer, and a compiling placeholder executable.
- Intentional deferral: VCaml command registration, Async process execution, response buffer creation, highlights, and Neovim state are not part of this milestone.
- Placeholder scan: no task uses unresolved placeholders; each code-facing step includes concrete paths, code snippets, commands, and expected results.
- Type consistency: module names, type names, and public signatures match the design spec and are referenced consistently across tasks.
