# VCaml Command Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a VCaml persistent plugin shell that registers freight commands and drives the pure core library without executing HTTP requests.

**Architecture:** Keep `lib/` pure. Add all VCaml, Async, and Core usage in `bin/`. Structure the executable around small helpers for state, scratch buffers, command handlers, and plugin startup so future curl execution can be added without rewriting command registration.

**Tech Stack:** OCaml, dune, VCaml, Async, Core, freight core library, jj.

---

## File structure

- Modify: `dune-project` — add executable dependencies `vcaml`, `async`, and `core`.
- Modify: `bin/dune` — link executable with `freight`, `vcaml`, `async`, and `core`.
- Replace: `bin/main.ml` — VCaml plugin entrypoint and command registration.
- Create: `bin/state.ml`, `bin/state.mli` — plugin state record and constructors.
- Create: `bin/scratch.ml`, `bin/scratch.mli` — Neovim scratch buffer helpers.
- Create: `bin/handlers.ml`, `bin/handlers.mli` — Freight command handlers.
- Create: `bin/request_view.ml`, `bin/request_view.mli` — pure formatting for parsed request/curl inspect output.
- Create: `test/test_request_view.ml` — pure tests for inspect rendering if executable-private modules are exposed through a test library.

If VCaml's exact API shape makes `scratch.ml` or `handlers.ml` awkward to test directly, keep Neovim-effectful code in `bin/` and test only pure formatting helpers.

---

### Task 1: Executable dependency setup

**Files:**

- Modify: `dune-project`
- Modify: `bin/dune`

- [ ] **Step 1: Add executable dependencies to `dune-project`**

In the package dependency list, add:

```lisp
vcaml
async
core
```

Keep `ounit2` test-only as `(ounit2 :with-test)`.

- [ ] **Step 2: Update `bin/dune` libraries**

Replace `bin/dune` with:

```lisp
(executable
 (public_name freight)
 (name main)
 (modules main state scratch handlers request_view)
 (libraries freight vcaml async core))
```

- [ ] **Step 3: Run build and capture dependency/API failures**

Run:

```bash
dune build
```

Expected: it may fail if VCaml is not installed. If dependency missing, install with opam or report BLOCKED with the exact missing package. Do not change `lib/dune`.

- [ ] **Step 4: Commit dependency setup**

Run:

```bash
jj describe -m "build(bin): add vcaml executable dependencies"
jj new
```

---

### Task 2: State and pure request inspect rendering

**Files:**

- Create: `bin/state.mli`
- Create: `bin/state.ml`
- Create: `bin/request_view.mli`
- Create: `bin/request_view.ml`
- Modify: `bin/dune`

- [ ] **Step 1: Create `bin/state.mli`**

```ocaml
type t = {
  mutable active_env : string option;
  mutable response_history : string list;
  mutable env : Freight.Env.t;
}

val create : unit -> t
val set_active_env : t -> string option -> unit
val remember_buffer : t -> string -> unit
```

- [ ] **Step 2: Create `bin/state.ml`**

```ocaml
type t = {
  mutable active_env : string option;
  mutable response_history : string list;
  mutable env : Freight.Env.t;
}

let create () =
  { active_env = None; response_history = []; env = Freight.Env.empty }

let set_active_env t active_env =
  t.active_env <- active_env

let remember_buffer t name =
  t.response_history <- name :: t.response_history
```

- [ ] **Step 3: Create `bin/request_view.mli`**

```ocaml
val render_request : Freight.Ast.request -> Freight.Executor.curl_invocation -> string list
val render_parse_error : Freight.Ast.parse_error -> string list
val render_message : title:string -> body:string list -> string list
```

- [ ] **Step 4: Create `bin/request_view.ml`**

```ocaml
let render_body = function
  | Freight.Ast.Body_none -> [ "Body: <none>" ]
  | Body_inline body -> [ "Body: inline"; body ]
  | Body_file path -> [ "Body: file " ^ path ]

let render_headers headers =
  match headers with
  | [] -> [ "Headers: <none>" ]
  | headers ->
      "Headers:"
      :: List.map (fun (key, value) -> "  " ^ key ^ ": " ^ value) headers

let render_request request invocation =
  let name = Option.value request.Freight.Ast.name ~default:"<unnamed>" in
  [ "Freight Inspect";
    "";
    "Name: " ^ name;
    "Method: " ^ Freight.Ast.method_to_string request.method_;
    "URL: " ^ request.url;
    "" ]
  @ render_headers request.headers
  @ [ "" ]
  @ render_body request.body
  @ [ ""; "Curl argv:" ]
  @ List.map (fun arg -> "  " ^ arg) invocation.Freight.Executor.args

let render_parse_error error =
  [ "Freight Parse Error";
    "";
    "Line: " ^ string_of_int error.Freight.Ast.line;
    "Message: " ^ error.message;
    "Snippet: " ^ error.snippet ]

let render_message ~title ~body =
  title :: "" :: body
```

If `Option.value` is unavailable in this compilation context, use a local match instead.

- [ ] **Step 5: Run build**

Run:

```bash
dune build
```

Expected: PASS, unless VCaml dependency remains unavailable from Task 1.

- [ ] **Step 6: Commit**

Run:

```bash
jj describe -m "feat(bin): add plugin state and inspect rendering"
jj new
```

---

### Task 3: Scratch buffer helper

**Files:**

- Create: `bin/scratch.mli`
- Create: `bin/scratch.ml`

- [ ] **Step 1: Inspect VCaml buffer/window API locally**

Run a targeted source/API search before coding:

```bash
opam var vcaml:lib
```

Then inspect installed `.mli` files for buffer creation, setting lines, setting options, and commands. Use the discovered API names exactly.

- [ ] **Step 2: Create `bin/scratch.mli`**

Design this interface, adapting types to actual VCaml API names:

```ocaml
val show : name:string -> filetype:string -> lines:string list -> unit Async.Deferred.t
```

- [ ] **Step 3: Create `bin/scratch.ml`**

Implement `show` to:

1. Create an unlisted scratch buffer.
2. Set its name to `name`.
3. Open or switch to it in a simple split/current window.
4. Set lines from `lines`.
5. Set `filetype`.
6. Set `modifiable=false`.

If a particular window action is hard with the installed VCaml API, use `nvim_command "vsplit"` or equivalent command API and document the choice in a code comment.

- [ ] **Step 4: Build**

Run:

```bash
dune build
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
jj describe -m "feat(bin): add freight scratch buffers"
jj new
```

---

### Task 4: Command handlers

**Files:**

- Create: `bin/handlers.mli`
- Create: `bin/handlers.ml`

- [ ] **Step 1: Create `bin/handlers.mli`**

Adapt VCaml callback argument types to the installed API. The logical interface should expose registration or individual handlers:

```ocaml
val freight_open : State.t -> unit Async.Deferred.t
val freight_env : State.t -> string option -> unit Async.Deferred.t
val freight_inspect : State.t -> unit Async.Deferred.t
val freight_run : State.t -> unit Async.Deferred.t
```

- [ ] **Step 2: Implement `FreightOpen` handler**

`freight_open` should call `Scratch.show` with:

```ocaml
~name:"freight://request"
~filetype:"http"
~lines:[ "GET https://example.com"; "" ]
```

- [ ] **Step 3: Implement `FreightEnv` handler**

`freight_env state active_env` should:

1. Update `state.active_env`.
2. Determine current buffer file directory if possible.
3. Reload `state.env` with `Freight.Env.load ~dir ~active_env` when a directory is available.
4. Show `freight://inspect` with active env status.

If current buffer path is unavailable, still update `active_env` and show a message explaining env files were not loaded.

- [ ] **Step 4: Implement `FreightInspect` handler**

For this milestone, try to read `freight_curl_cmd` buffer-local variable using VCaml. If missing or unsupported, show:

```text
Freight Inspect

No freight_curl_cmd metadata on current buffer yet.
```

- [ ] **Step 5: Implement `FreightRun` handler**

`freight_run state` should:

1. Read current buffer lines.
2. Join with `\n`.
3. Parse with `Freight.Parser.parse_string`.
4. On parse error, show `freight://error` using `Request_view.render_parse_error`.
5. On success, select request with `Freight.Parser.request_at_cursor file.requests cursor_line`.
6. Substitute env into URL, headers, and body/body-file path.
7. Build invocation with `Freight.Executor.to_curl`.
8. Show `freight://inspect` using `Request_view.render_request`.

Do not execute curl.

- [ ] **Step 6: Build**

Run:

```bash
dune build
```

Expected: PASS.

- [ ] **Step 7: Commit**

Run:

```bash
jj describe -m "feat(bin): add freight command handlers"
jj new
```

---

### Task 5: Plugin entrypoint and registration

**Files:**

- Replace: `bin/main.ml`

- [ ] **Step 1: Inspect VCaml plugin registration examples**

Search installed docs/examples or package files for persistent plugin setup and user command creation. Prefer exact local examples over guessing API names.

- [ ] **Step 2: Replace `bin/main.ml`**

Implement plugin startup to:

1. Create `State.t`.
2. Register global commands:
   - `FreightOpen`
   - `FreightEnv` with optional argument
   - `FreightInspect`
   - `FreightRun`
3. Register `BufEnter` autocmd for `*.http,*.rest` setting `filetype=http` if not already set.
4. Start/block on the VCaml/Async event loop using the installed VCaml API.

- [ ] **Step 3: Build**

Run:

```bash
dune build
```

Expected: PASS.

- [ ] **Step 4: Commit**

Run:

```bash
jj describe -m "feat(bin): register vcaml freight plugin commands"
jj new
```

---

### Task 6: Manual smoke instructions and final verification

**Files:**

- Create: `docs/superpowers/manual-tests/2026-05-24-vcaml-command-shell.md`

- [ ] **Step 1: Write manual test instructions**

Create the file with:

```markdown
# VCaml Command Shell Manual Smoke Test

## Preconditions

- `dune build` succeeds.
- Neovim can load the built freight executable through the local VCaml plugin loading workflow.

## Cases

1. Start Neovim with freight plugin loaded.
2. Run `:FreightOpen`.
   - Expected: scratch request buffer opens with `filetype=http`.
3. Enter a simple request:
   ```http
   GET https://example.com

   ```
4. Run `:FreightRun`.
   - Expected: `freight://inspect` buffer opens with method, URL, and curl argv.
   - Expected: no HTTP request is executed.
5. Replace request with malformed text and run `:FreightRun`.
   - Expected: `freight://error` buffer opens with parse details.
6. Run `:FreightEnv dev`.
   - Expected: inspect/info buffer reports active env `dev`.
7. Run `:FreightInspect` from a normal buffer.
   - Expected: friendly diagnostic about missing `freight_curl_cmd` metadata.
```

- [ ] **Step 2: Run final build and tests**

Run:

```bash
dune build && dune runtest
```

Expected: PASS.

- [ ] **Step 3: Inspect dependency boundary**

Run:

```bash
grep -R "vcaml\|Async\|Core" -n lib || true
```

Expected: no matches proving VCaml/Async/Core stayed out of `lib/`.

- [ ] **Step 4: Commit final docs/verification**

Run:

```bash
jj describe -m "docs(bin): add vcaml smoke test checklist"
jj new
```

---

## Self-review

- Spec coverage: tasks cover executable dependencies, plugin state, scratch buffers, four commands, autocmd, parse-only `FreightRun`, inspect/error buffers, and manual smoke tests.
- Intentional deferral: curl execution, real response rendering, response history navigation, chaining execution, rich floating UI, and parser cursor-range redesign remain out of scope.
- Dependency boundary: plan keeps VCaml/Async/Core in `bin/` only.
- Placeholder scan: API names that depend on installed VCaml are explicitly discovered before implementation rather than guessed.
